#include "katago_c_api.h"

#include "core/config_parser.h"
#include "core/global.h"
#include "core/logger.h"
#include "core/rand.h"
#include "game/board.h"
#include "game/boardhistory.h"
#include "game/rules.h"
#include "neuralnet/nninputs.h"
#include "neuralnet/nneval.h"
#include "neuralnet/sgfmetadata.h"
#include "program/play.h"
#include "program/playutils.h"
#include "program/setup.h"
#include "search/analysisdata.h"
#include "search/asyncbot.h"
#include "search/reportedsearchvalues.h"
#include "search/searchparams.h"
#include "search/timecontrols.h"

#include <cmath>
#include <cstring>
#include <exception>
#include <iomanip>
#include <locale>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

using namespace std;

namespace {

constexpr const char* kVersion = "city_katago_embed/0.4 (KataGo Eigen Human-SL)";

// Candidate moves reported alongside a generated move. Enough for a board overlay,
// small enough that the JSON can never approach the caller's buffer.
constexpr int kMaxCandidates = 6;

bool is_valid_rank_token(const string& rank) {
  static const char* kRanks[] = {
    "20k", "19k", "18k", "17k", "16k", "15k", "14k", "13k", "12k", "11k",
    "10k", "9k", "8k", "7k", "6k", "5k", "4k", "3k", "2k", "1k",
    "1d", "2d", "3d", "4d", "5d", "6d", "7d", "8d", "9d",
  };
  for(const char* r : kRanks) {
    if(rank == r)
      return true;
  }
  return false;
}

void write_err(char* err, int err_len, const string& msg) {
  if(err == nullptr || err_len <= 0)
    return;
  if(msg.empty()) {
    err[0] = '\0';
    return;
  }
  const size_t n = static_cast<size_t>(err_len - 1);
  strncpy(err, msg.c_str(), n);
  err[n] = '\0';
}

Player parse_color(const char* color) {
  Player pla = C_EMPTY;
  if(color == nullptr || !PlayerIO::tryParsePlayer(string(color), pla))
    throw StringError(string("invalid color: ") + (color ? color : "(null)"));
  if(pla != P_BLACK && pla != P_WHITE)
    throw StringError(string("invalid color: ") + color);
  return pla;
}

// Classic locale so the decimal point is always '.' regardless of the host process.
string json_number(double v, int decimals) {
  ostringstream o;
  o.imbue(std::locale::classic());
  o << std::fixed << std::setprecision(decimals) << v;
  return o.str();
}

// KataGo reports search values from White's perspective; the game speaks Black.
double black_winrate_of(double win_loss_value) {
  return 1.0 - 0.5 * (1.0 + win_loss_value);
}

// Mirror KataGo GTP: suppress Human-SL bias while estimating endgame ownership / lead.
SearchParams scoring_search_params(const SearchParams& base) {
  SearchParams tmp = base;
  tmp.playoutDoublingAdvantage = 0.0;
  tmp.conservativePass = true;
  tmp.humanSLChosenMoveProp = 0.0;
  tmp.humanSLRootExploreProbWeightful = 0.0;
  tmp.humanSLRootExploreProbWeightless = 0.0;
  tmp.humanSLPlaExploreProbWeightful = 0.0;
  tmp.humanSLPlaExploreProbWeightless = 0.0;
  tmp.humanSLOppExploreProbWeightful = 0.0;
  tmp.humanSLOppExploreProbWeightless = 0.0;
  tmp.antiMirror = false;
  tmp.avoidRepeatedPatternUtility = 0;
  return tmp;
}

bool hist_has_strict_finished_score(const BoardHistory& hist) {
  return hist.isGameFinished && (
    (hist.rules.scoringRule == Rules::SCORING_AREA && !hist.rules.friendlyPassOk) ||
    (hist.rules.scoringRule == Rules::SCORING_TERRITORY)
  );
}

} // namespace

struct KatagoHandle {
  ConfigParser cfg;
  Logger logger;
  Rand seed_rand;
  NNEvaluator* nn_eval = nullptr;
  AsyncBot* bot = nullptr;
  Rules rules;
  int board_size = 19;
  string last_error;
  string rank_token = "5k";

  KatagoHandle()
    : cfg(),
      // Logger must not read cfg at construct time — we initialize cfg after.
      logger(nullptr, false, false, true, false),
      seed_rand("city_katago_embed")
  {}

  ~KatagoHandle() {
    if(bot != nullptr) {
      bot->stopAndWait();
      delete bot;
      bot = nullptr;
    }
    if(nn_eval != nullptr) {
      delete nn_eval;
      nn_eval = nullptr;
    }
  }

  void set_error(const string& msg) {
    last_error = msg;
  }

  void reset_board() {
    Board board(board_size, board_size);
    Player pla = P_BLACK;
    BoardHistory hist(board, pla, rules, 0);
    bot->setPosition(pla, board, hist);
  }
};

namespace {

// Read what the finished search already computed. Must run before makeMove reroots
// the tree. Returns "{}" when the search has nothing usable (e.g. zero visits).
string collect_root_eval_json(const KatagoHandle* h) {
  const Search* search = h->bot->getSearch();
  if(search == nullptr)
    return "{}";

  ReportedSearchValues values;
  if(!search->getRootValues(values))
    return "{}";
  if(!std::isfinite(values.winLossValue) || !std::isfinite(values.lead))
    return "{}";

  const Board& board = h->bot->getRootBoard();
  ostringstream out;
  out.imbue(std::locale::classic());
  out << "{\"winrate_black\":" << json_number(black_winrate_of(values.winLossValue), 4);
  out << ",\"lead_black\":" << json_number(-values.lead, 2);
  out << ",\"visits\":" << values.visits;
  out << ",\"candidates\":[";

  // PV depth 1: we want the move and its stats, not a whole variation.
  vector<AnalysisData> buf;
  search->getAnalysisData(buf, kMaxCandidates, false, 1, false);
  int written = 0;
  for(size_t i = 0; i < buf.size() && written < kMaxCandidates; i++) {
    const AnalysisData& d = buf[i];
    if(d.move == Board::NULL_LOC)
      continue;
    if(!std::isfinite(d.winLossValue) || !std::isfinite(d.lead))
      continue;
    const string vertex =
      (d.move == Board::PASS_LOC) ? string("pass") : Location::toString(d.move, board);
    if(written > 0)
      out << ",";
    out << "{\"vertex\":\"" << vertex << "\"";
    out << ",\"visits\":" << d.numVisits;
    out << ",\"winrate_black\":" << json_number(black_winrate_of(d.winLossValue), 4);
    out << ",\"lead_black\":" << json_number(-d.lead, 2);
    out << ",\"order\":" << d.order;
    out << "}";
    written++;
  }
  out << "]}";
  return out.str();
}

} // namespace

extern "C" {

const char* katago_version(void) {
  return kVersion;
}

KatagoHandle* katago_create(
  const char* model_path,
  const char* config_path,
  int max_visits,
  char* err,
  int err_len
) {
  if(model_path == nullptr || model_path[0] == '\0') {
    write_err(err, err_len, "model_path is empty");
    return nullptr;
  }
  if(config_path == nullptr || config_path[0] == '\0') {
    write_err(err, err_len, "config_path is empty");
    return nullptr;
  }
  if(max_visits < 1) {
    write_err(err, err_len, "max_visits must be >= 1");
    return nullptr;
  }

  unique_ptr<KatagoHandle> h(new KatagoHandle());
  try {
    // Required once per process (same as KataGo GTP main).
    Board::initHash();
    ScoreValue::initTables();

    h->cfg.initialize(string(config_path));
    h->cfg.overrideKey("maxVisits", Global::intToString(max_visits));
    // Keep embed quiet unless the host wants files; avoid relative logDir surprises.
    h->cfg.overrideKey("logToStderr", "false");
    h->cfg.overrideKey("logAllGTPCommunication", "false");
    h->cfg.overrideKey("logSearchInfo", "false");
    // Default Human-SL profile when config omitted it (human net requires metadata).
    if(!h->cfg.contains("humanSLProfile"))
      h->cfg.overrideKey("humanSLProfile", "rank_5k");

    Setup::initializeSession(h->cfg);
    SearchParams params = Setup::loadSingleParams(h->cfg, Setup::SETUP_FOR_GTP);
    params.maxVisits = max_visits;
    params.maxPlayouts = max_visits;

    h->rules = Setup::loadSingleRules(h->cfg, true);

    const int expectedConcurrentEvals = std::max(params.numThreads, 1);
    const int defaultMaxBatchSize = std::max(8, ((expectedConcurrentEvals + 3) / 4) * 4);
    const string expectedSha256 = "";
    const string model(model_path);

    h->nn_eval = Setup::initializeNNEvaluator(
      model,
      model,
      expectedSha256,
      h->cfg,
      h->logger,
      h->seed_rand,
      expectedConcurrentEvals,
      19,
      19,
      defaultMaxBatchSize,
      false,
      false,
      Setup::SETUP_FOR_GTP
    );

    bool rulesOk = false;
    h->nn_eval->getSupportedRules(h->rules, rulesOk);
    if(!rulesOk)
      throw StringError("rules from config are not supported by neural net");

    const string searchRandSeed = Global::uint64ToString(h->seed_rand.nextUInt64());
    h->bot = new AsyncBot(params, h->nn_eval, &h->logger, searchRandSeed);
    h->board_size = 19;
    h->reset_board();
  }
  catch(const StringError& e) {
    write_err(err, err_len, string(e.what()));
    return nullptr;
  }
  catch(const exception& e) {
    write_err(err, err_len, string(e.what()));
    return nullptr;
  }
  catch(const string& e) {
    write_err(err, err_len, e);
    return nullptr;
  }
  catch(...) {
    write_err(err, err_len, "unknown error during katago_create");
    return nullptr;
  }

  write_err(err, err_len, "");
  return h.release();
}

void katago_destroy(KatagoHandle* h) {
  delete h;
}

const char* katago_last_error(const KatagoHandle* h) {
  if(h == nullptr)
    return "null handle";
  return h->last_error.c_str();
}

int katago_set_boardsize(KatagoHandle* h, int n) {
  if(h == nullptr || h->bot == nullptr)
    return 1;
  try {
    if(n < 2 || n > Board::MAX_LEN)
      throw StringError("boardsize out of range");
    h->bot->stopAndWait();
    h->board_size = n;
    h->reset_board();
    h->last_error.clear();
    return 0;
  }
  catch(const StringError& e) {
    h->set_error(string(e.what()));
    return 1;
  }
  catch(const exception& e) {
    h->set_error(string(e.what()));
    return 1;
  }
  catch(const string& e) {
    h->set_error(e);
    return 1;
  }
}

int katago_clear_board(KatagoHandle* h) {
  if(h == nullptr || h->bot == nullptr)
    return 1;
  try {
    h->bot->stopAndWait();
    h->reset_board();
    h->last_error.clear();
    return 0;
  }
  catch(const StringError& e) {
    h->set_error(string(e.what()));
    return 1;
  }
  catch(const exception& e) {
    h->set_error(string(e.what()));
    return 1;
  }
  catch(const string& e) {
    h->set_error(e);
    return 1;
  }
}

int katago_set_rank(KatagoHandle* h, const char* rank) {
  if(h == nullptr || h->bot == nullptr)
    return 1;
  try {
    if(rank == nullptr || rank[0] == '\0')
      throw StringError("rank is empty");
    string token = Global::toLower(string(rank));
    if(!is_valid_rank_token(token))
      throw StringError(string("invalid rank (want 20k..1k or 1d..9d): ") + token);
    string profileName = string("rank_") + token;
    SGFMetadata profile = SGFMetadata::getProfile(profileName);
    if(!profile.initialized)
      throw StringError(string("failed to resolve humanSLProfile ") + profileName);

    h->bot->stopAndWait();
    SearchParams params = h->bot->getParams();
    params.humanSLProfile = profile;
    h->bot->setParams(params);
    h->cfg.overrideKey("humanSLProfile", profileName);
    h->rank_token = token;
    h->last_error.clear();
    return 0;
  }
  catch(const StringError& e) {
    h->set_error(string(e.what()));
    return 1;
  }
  catch(const exception& e) {
    h->set_error(string(e.what()));
    return 1;
  }
  catch(const string& e) {
    h->set_error(e);
    return 1;
  }
}

int katago_play(KatagoHandle* h, const char* color, const char* vertex) {
  if(h == nullptr || h->bot == nullptr)
    return 1;
  try {
    const Player pla = parse_color(color);
    if(vertex == nullptr)
      throw StringError("vertex is null");
    Loc loc = Board::NULL_LOC;
    const string v(vertex);
    if(Global::toLower(v) == "pass")
      loc = Board::PASS_LOC;
    else if(!Location::tryOfString(v, h->bot->getRootBoard(), loc))
      throw StringError(string("invalid vertex: ") + v);

    h->bot->stopAndWait();
    if(!h->bot->makeMove(loc, pla))
      throw StringError(string("illegal move: ") + v);
    h->last_error.clear();
    return 0;
  }
  catch(const StringError& e) {
    h->set_error(string(e.what()));
    return 1;
  }
  catch(const exception& e) {
    h->set_error(string(e.what()));
    return 1;
  }
  catch(const string& e) {
    h->set_error(e);
    return 1;
  }
}

int katago_set_komi(KatagoHandle* h, float komi) {
  if(h == nullptr || h->bot == nullptr)
    return 1;
  try {
    if(!Rules::komiIsIntOrHalfInt(komi))
      throw StringError("komi must be an integer or half-integer");
    if(komi < Rules::MIN_USER_KOMI || komi > Rules::MAX_USER_KOMI)
      throw StringError("komi out of range");
    h->bot->stopAndWait();
    const Player pla = h->bot->getRootPla();
    const Board board = h->bot->getRootBoard();
    BoardHistory hist = h->bot->getRootHist();
    hist.setKomi(komi);
    h->rules = hist.rules;
    h->bot->setPosition(pla, board, hist);
    h->last_error.clear();
    return 0;
  }
  catch(const StringError& e) {
    h->set_error(string(e.what()));
    return 1;
  }
  catch(const exception& e) {
    h->set_error(string(e.what()));
    return 1;
  }
  catch(const string& e) {
    h->set_error(e);
    return 1;
  }
}

int katago_genmove(KatagoHandle* h, const char* color, char* out_vertex, int out_len) {
  if(h == nullptr || h->bot == nullptr)
    return 1;
  if(out_vertex == nullptr || out_len < 8)
    return 1;
  try {
    const Player pla = parse_color(color);
    TimeControls tc;
    Loc loc = h->bot->genMoveSynchronous(pla, tc);
    if(loc == Board::NULL_LOC)
      throw StringError("genmove returned null location");
    if(!h->bot->makeMove(loc, pla))
      throw StringError("genmove chose illegal move");

    string s;
    if(loc == Board::PASS_LOC)
      s = "pass";
    else
      s = Location::toString(loc, h->bot->getRootBoard());

    write_err(out_vertex, out_len, s);
    h->last_error.clear();
    return 0;
  }
  catch(const StringError& e) {
    h->set_error(string(e.what()));
    return 1;
  }
  catch(const exception& e) {
    h->set_error(string(e.what()));
    return 1;
  }
  catch(const string& e) {
    h->set_error(e);
    return 1;
  }
}

int katago_genmove_eval(
  KatagoHandle* h,
  const char* color,
  char* out_vertex,
  int out_vertex_len,
  char* out_eval_json,
  int out_eval_json_len
) {
  if(h == nullptr || h->bot == nullptr)
    return 1;
  if(out_vertex == nullptr || out_vertex_len < 8)
    return 1;
  if(out_eval_json == nullptr || out_eval_json_len < 3)
    return 1;
  try {
    const Player pla = parse_color(color);
    TimeControls tc;
    Loc loc = h->bot->genMoveSynchronous(pla, tc);
    if(loc == Board::NULL_LOC)
      throw StringError("genmove returned null location");

    // Harvest first: makeMove reroots the tree and drops the root stats.
    string eval_json = collect_root_eval_json(h);
    if(static_cast<int>(eval_json.size()) + 1 > out_eval_json_len)
      eval_json = "{}";

    if(!h->bot->makeMove(loc, pla))
      throw StringError("genmove chose illegal move");

    string s;
    if(loc == Board::PASS_LOC)
      s = "pass";
    else
      s = Location::toString(loc, h->bot->getRootBoard());

    write_err(out_vertex, out_vertex_len, s);
    write_err(out_eval_json, out_eval_json_len, eval_json);
    h->last_error.clear();
    return 0;
  }
  catch(const StringError& e) {
    h->set_error(string(e.what()));
    return 1;
  }
  catch(const exception& e) {
    h->set_error(string(e.what()));
    return 1;
  }
  catch(const string& e) {
    h->set_error(e);
    return 1;
  }
}

int katago_final_score(KatagoHandle* h, char* out_score, int out_len) {
  if(h == nullptr || h->bot == nullptr)
    return 1;
  if(out_score == nullptr || out_len < 8)
    return 1;
  bool restored = true;
  SearchParams saved_params;
  Player old_pla = C_EMPTY;
  Board old_board;
  BoardHistory old_hist;
  try {
    h->bot->stopAndWait();
    saved_params = h->bot->getParams();
    old_pla = h->bot->getRootPla();
    old_board = h->bot->getRootBoard();
    old_hist = h->bot->getRootHist();
    restored = false;
    h->bot->setParams(scoring_search_params(saved_params));

    Board board = old_board;
    BoardHistory hist = old_hist;
    Player pla = old_pla;

    Player winner = C_EMPTY;
    double final_white_minus_black = 0.0;
    if(hist_has_strict_finished_score(hist)) {
      winner = hist.winner;
      final_white_minus_black = hist.finalWhiteMinusBlackScore;
    }
    else {
      const int64_t num_visits = std::max<int64_t>(50, static_cast<int64_t>(saved_params.numThreads) * 10);
      double lead = PlayUtils::computeLead(
        h->bot->getSearchStopAndWait(),
        nullptr,
        board,
        hist,
        pla,
        num_visits,
        OtherGameProperties()
      );
      if(hist.rules.gameResultWillBeInteger())
        lead = round(lead);
      else
        lead = round(lead + 0.5) - 0.5;
      final_white_minus_black = lead;
      winner = lead > 0 ? P_WHITE : (lead < 0 ? P_BLACK : C_EMPTY);
    }

    h->bot->setPosition(old_pla, old_board, old_hist);
    h->bot->setParams(saved_params);
    restored = true;

    string response;
    if(winner == C_EMPTY)
      response = "0";
    else {
      ostringstream o;
      o.imbue(std::locale::classic());
      o << (winner == P_BLACK ? "B+" : "W+") << std::fixed << std::setprecision(1)
        << std::fabs(final_white_minus_black);
      response = o.str();
    }
    write_err(out_score, out_len, response);
    h->last_error.clear();
    return 0;
  }
  catch(const StringError& e) {
    if(!restored) {
      h->bot->setPosition(old_pla, old_board, old_hist);
      h->bot->setParams(saved_params);
    }
    h->set_error(string(e.what()));
    return 1;
  }
  catch(const exception& e) {
    if(!restored) {
      h->bot->setPosition(old_pla, old_board, old_hist);
      h->bot->setParams(saved_params);
    }
    h->set_error(string(e.what()));
    return 1;
  }
  catch(const string& e) {
    if(!restored) {
      h->bot->setPosition(old_pla, old_board, old_hist);
      h->bot->setParams(saved_params);
    }
    h->set_error(e);
    return 1;
  }
}

int katago_final_status_list(
  KatagoHandle* h,
  const char* which,
  char* out_vertices,
  int out_len
) {
  if(h == nullptr || h->bot == nullptr)
    return 1;
  if(which == nullptr || out_vertices == nullptr || out_len < 2)
    return 1;
  bool restored = true;
  SearchParams saved_params;
  Player old_pla = C_EMPTY;
  Board old_board;
  BoardHistory old_hist;
  try {
    const string mode = Global::toLower(string(which));
    int status_mode = -1;
    if(mode == "alive")
      status_mode = 0;
    else if(mode == "seki")
      status_mode = 1;
    else if(mode == "dead")
      status_mode = 2;
    else
      throw StringError("final_status_list which must be alive, seki, or dead");

    h->bot->stopAndWait();
    saved_params = h->bot->getParams();
    old_pla = h->bot->getRootPla();
    old_board = h->bot->getRootBoard();
    old_hist = h->bot->getRootHist();
    restored = false;
    h->bot->setParams(scoring_search_params(saved_params));

    Board board = old_board;
    BoardHistory hist = old_hist;
    Player pla = old_pla;

    vector<bool> is_alive;
    if(hist_has_strict_finished_score(hist))
      is_alive = PlayUtils::computeAnticipatedStatusesSimple(board, hist);
    else {
      const int64_t num_visits = std::max<int64_t>(100, static_cast<int64_t>(saved_params.numThreads) * 20);
      vector<double> ownerships_buf;
      is_alive = PlayUtils::computeAnticipatedStatusesWithOwnership(
        h->bot->getSearchStopAndWait(),
        board,
        hist,
        pla,
        num_visits,
        ownerships_buf
      );
    }

    h->bot->setPosition(old_pla, old_board, old_hist);
    h->bot->setParams(saved_params);
    restored = true;

    // GTP: seki list is empty; alive/dead come from the ownership boolean map.
    ostringstream out;
    bool first = true;
    for(int y = 0; y < board.y_size; y++) {
      for(int x = 0; x < board.x_size; x++) {
        const Loc loc = Location::getLoc(x, y, board.x_size);
        if(board.colors[loc] == C_EMPTY)
          continue;
        const bool alive = is_alive[loc];
        const bool want =
          (status_mode == 0 && alive) ||
          (status_mode == 2 && !alive);
        if(status_mode == 1 || !want)
          continue;
        if(!first)
          out << ' ';
        first = false;
        out << Location::toString(loc, board);
      }
    }
    write_err(out_vertices, out_len, out.str());
    h->last_error.clear();
    return 0;
  }
  catch(const StringError& e) {
    if(!restored) {
      h->bot->setPosition(old_pla, old_board, old_hist);
      h->bot->setParams(saved_params);
    }
    h->set_error(string(e.what()));
    return 1;
  }
  catch(const exception& e) {
    if(!restored) {
      h->bot->setPosition(old_pla, old_board, old_hist);
      h->bot->setParams(saved_params);
    }
    h->set_error(string(e.what()));
    return 1;
  }
  catch(const string& e) {
    if(!restored) {
      h->bot->setPosition(old_pla, old_board, old_hist);
      h->bot->setParams(saved_params);
    }
    h->set_error(e);
    return 1;
  }
}

} // extern "C"

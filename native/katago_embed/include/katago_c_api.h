#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#ifdef _WIN32
#ifdef KATAGO_EMBED_EXPORTS
#define KATAGO_API __declspec(dllexport)
#else
#define KATAGO_API __declspec(dllimport)
#endif
#else
#define KATAGO_API
#endif

typedef struct KatagoHandle KatagoHandle;

/** Create engine: loads model + config. Returns null on failure; write reason into err. */
KATAGO_API KatagoHandle* katago_create(
  const char* model_path,
  const char* config_path,
  int max_visits,
  char* err,
  int err_len
);

KATAGO_API void katago_destroy(KatagoHandle* h);

/** 0 = ok, nonzero = error (see katago_last_error). */
KATAGO_API int katago_set_boardsize(KatagoHandle* h, int n);
KATAGO_API int katago_clear_board(KatagoHandle* h);

/**
 * Set Human-SL strength profile. `rank` is "20k"…"1k" or "1d"…"9d"
 * (maps to humanSLProfile = rank_<rank>). Returns 0 on success.
 */
KATAGO_API int katago_set_rank(KatagoHandle* h, const char* rank);

/** color: "b"/"w"/"black"/"white". vertex: GTP coords or "pass". */
KATAGO_API int katago_play(KatagoHandle* h, const char* color, const char* vertex);

/** Set komi on the live history (does not clear the board). */
KATAGO_API int katago_set_komi(KatagoHandle* h, float komi);

/**
 * Generate and play a move for color. Writes GTP vertex (or "pass") into out_vertex.
 * Returns 0 on success.
 */
KATAGO_API int katago_genmove(KatagoHandle* h, const char* color, char* out_vertex, int out_len);

/**
 * Same as katago_genmove, plus the root statistics the very same search already produced
 * (no second search, no ownership aggregation). Writes a JSON object into out_eval_json:
 *
 *   {"winrate_black":0.5432,"lead_black":-2.30,"visits":40,
 *    "candidates":[{"vertex":"D4","visits":18,"winrate_black":0.55,
 *                   "lead_black":1.20,"order":0}, ...]}
 *
 * All winrates and leads are normalized to Black's perspective. "{}" means the search
 * reported nothing usable. Returns 0 on success.
 */
KATAGO_API int katago_genmove_eval(
  KatagoHandle* h,
  const char* color,
  char* out_vertex,
  int out_vertex_len,
  char* out_eval_json,
  int out_eval_json_len
);

/**
 * GTP-compatible endgame score (mirrors KataGo `final_score`). Writes "B+12.5", "W+3.5",
 * or "0" into out_score. Uses NN lead when the ruleset has not finished a strict score.
 */
KATAGO_API int katago_final_score(KatagoHandle* h, char* out_score, int out_len);

/**
 * GTP-compatible life/death list (mirrors KataGo `final_status_list`).
 * `which` must be "alive", "seki", or "dead". Writes space-separated GTP vertices.
 * Dead stones come from NN ownership when the game is not strictly finished.
 */
KATAGO_API int katago_final_status_list(
  KatagoHandle* h,
  const char* which,
  char* out_vertices,
  int out_len
);

KATAGO_API const char* katago_last_error(const KatagoHandle* h);
KATAGO_API const char* katago_version(void);

#ifdef __cplusplus
}
#endif

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

/**
 * Generate and play a move for color. Writes GTP vertex (or "pass") into out_vertex.
 * Returns 0 on success.
 */
KATAGO_API int katago_genmove(KatagoHandle* h, const char* color, char* out_vertex, int out_len);

KATAGO_API const char* katago_last_error(const KatagoHandle* h);
KATAGO_API const char* katago_version(void);

#ifdef __cplusplus
}
#endif

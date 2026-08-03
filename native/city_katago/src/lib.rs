use godot::prelude::*;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;

mod ffi {
    use super::*;

    #[repr(C)]
    pub struct KatagoHandle {
        _private: [u8; 0],
    }

    unsafe extern "C" {
        pub fn katago_create(
            model_path: *const c_char,
            config_path: *const c_char,
            max_visits: i32,
            err: *mut c_char,
            err_len: i32,
        ) -> *mut KatagoHandle;

        pub fn katago_destroy(h: *mut KatagoHandle);
        pub fn katago_set_boardsize(h: *mut KatagoHandle, n: i32) -> i32;
        pub fn katago_clear_board(h: *mut KatagoHandle) -> i32;
        pub fn katago_set_rank(h: *mut KatagoHandle, rank: *const c_char) -> i32;
        pub fn katago_play(
            h: *mut KatagoHandle,
            color: *const c_char,
            vertex: *const c_char,
        ) -> i32;
        pub fn katago_genmove(
            h: *mut KatagoHandle,
            color: *const c_char,
            out_vertex: *mut c_char,
            out_len: i32,
        ) -> i32;
        pub fn katago_genmove_eval(
            h: *mut KatagoHandle,
            color: *const c_char,
            out_vertex: *mut c_char,
            out_vertex_len: i32,
            out_eval_json: *mut c_char,
            out_eval_json_len: i32,
        ) -> i32;
        pub fn katago_last_error(h: *const KatagoHandle) -> *const c_char;
        pub fn katago_version() -> *const c_char;
    }
}

struct CityKatagoExtension;

#[gdextension]
unsafe impl ExtensionLibrary for CityKatagoExtension {}

fn c_str_to_gstring(p: *const c_char) -> GString {
    if p.is_null() {
        return GString::new();
    }
    // SAFETY: C API returns NUL-terminated UTF-8 / ASCII.
    let s = unsafe { CStr::from_ptr(p) };
    GString::from(s.to_string_lossy().as_ref())
}

fn last_error(h: *mut ffi::KatagoHandle) -> String {
    if h.is_null() {
        return "null handle".to_string();
    }
    let p = unsafe { ffi::katago_last_error(h) };
    if p.is_null() {
        return "unknown error".to_string();
    }
    unsafe { CStr::from_ptr(p) }
        .to_string_lossy()
        .into_owned()
}

#[derive(GodotClass)]
#[class(base=RefCounted)]
struct NativeKataGo {
    base: Base<RefCounted>,
    handle: *mut ffi::KatagoHandle,
}

impl Drop for NativeKataGo {
    fn drop(&mut self) {
        self.destroy_handle();
    }
}

#[godot_api]
impl IRefCounted for NativeKataGo {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            base,
            handle: ptr::null_mut(),
        }
    }
}

#[godot_api]
impl NativeKataGo {
    #[func]
    fn version() -> GString {
        c_str_to_gstring(unsafe { ffi::katago_version() })
    }

    #[func]
    fn is_loaded(&self) -> bool {
        !self.handle.is_null()
    }

    /// Load Eigen-backed KataGo. Paths are absolute filesystem paths (not res://).
    #[func]
    fn load(&mut self, model_path: GString, config_path: GString, max_visits: i32) -> bool {
        self.destroy_handle();
        let model = match CString::new(model_path.to_string()) {
            Ok(s) => s,
            Err(_) => {
                godot_error!("NativeKataGo.load: model_path contains interior NUL");
                return false;
            }
        };
        let config = match CString::new(config_path.to_string()) {
            Ok(s) => s,
            Err(_) => {
                godot_error!("NativeKataGo.load: config_path contains interior NUL");
                return false;
            }
        };
        let mut err = vec![0 as c_char; 1024];
        let h = unsafe {
            ffi::katago_create(
                model.as_ptr(),
                config.as_ptr(),
                max_visits,
                err.as_mut_ptr(),
                err.len() as i32,
            )
        };
        if h.is_null() {
            let msg = unsafe { CStr::from_ptr(err.as_ptr() as *const c_char) }
                .to_string_lossy()
                .into_owned();
            godot_error!("NativeKataGo.load failed: {msg}");
            return false;
        }
        self.handle = h;
        true
    }

    #[func]
    fn unload(&mut self) {
        self.destroy_handle();
    }

    #[func]
    fn set_boardsize(&mut self, n: i32) {
        self.require_handle();
        let rc = unsafe { ffi::katago_set_boardsize(self.handle, n) };
        if rc != 0 {
            panic!("NativeKataGo.set_boardsize failed: {}", last_error(self.handle));
        }
    }

    #[func]
    fn clear_board(&mut self) {
        self.require_handle();
        let rc = unsafe { ffi::katago_clear_board(self.handle) };
        if rc != 0 {
            panic!("NativeKataGo.clear_board failed: {}", last_error(self.handle));
        }
    }

    /// Human-SL rank token: "20k"…"1k" or "1d"…"9d".
    #[func]
    fn set_rank(&mut self, rank: GString) {
        self.require_handle();
        let r = CString::new(rank.to_string()).expect("rank NUL");
        let rc = unsafe { ffi::katago_set_rank(self.handle, r.as_ptr()) };
        if rc != 0 {
            panic!("NativeKataGo.set_rank failed: {}", last_error(self.handle));
        }
    }

    #[func]
    fn play(&mut self, color: GString, vertex: GString) {
        self.require_handle();
        let c = CString::new(color.to_string()).expect("color NUL");
        let v = CString::new(vertex.to_string()).expect("vertex NUL");
        let rc = unsafe { ffi::katago_play(self.handle, c.as_ptr(), v.as_ptr()) };
        if rc != 0 {
            panic!("NativeKataGo.play failed: {}", last_error(self.handle));
        }
    }

    /// Generate and play a move. Returns GTP vertex (e.g. "D4") or "pass".
    #[func]
    fn genmove(&mut self, color: GString) -> GString {
        self.require_handle();
        let c = CString::new(color.to_string()).expect("color NUL");
        let mut out = vec![0 as c_char; 32];
        let rc = unsafe {
            ffi::katago_genmove(self.handle, c.as_ptr(), out.as_mut_ptr(), out.len() as i32)
        };
        if rc != 0 {
            panic!("NativeKataGo.genmove failed: {}", last_error(self.handle));
        }
        c_str_to_gstring(out.as_ptr() as *const c_char)
    }

    /// Generate and play a move, also returning the root statistics that same search
    /// already produced. Keys: "vertex" (GTP vertex or "pass") and "eval_json"
    /// (JSON object, "{}" when the search reported nothing usable).
    #[func]
    fn genmove_eval(&mut self, color: GString) -> VarDictionary {
        self.require_handle();
        let c = CString::new(color.to_string()).expect("color NUL");
        let mut out = vec![0 as c_char; 32];
        let mut json = vec![0 as c_char; 4096];
        let rc = unsafe {
            ffi::katago_genmove_eval(
                self.handle,
                c.as_ptr(),
                out.as_mut_ptr(),
                out.len() as i32,
                json.as_mut_ptr(),
                json.len() as i32,
            )
        };
        if rc != 0 {
            panic!(
                "NativeKataGo.genmove_eval failed: {}",
                last_error(self.handle)
            );
        }
        let mut dict = VarDictionary::new();
        dict.set(
            "vertex",
            &c_str_to_gstring(out.as_ptr() as *const c_char),
        );
        dict.set(
            "eval_json",
            &c_str_to_gstring(json.as_ptr() as *const c_char),
        );
        dict
    }
}

impl NativeKataGo {
    fn require_handle(&self) {
        if self.handle.is_null() {
            panic!("NativeKataGo: not loaded — call load() first");
        }
    }

    fn destroy_handle(&mut self) {
        if !self.handle.is_null() {
            unsafe { ffi::katago_destroy(self.handle) };
            self.handle = ptr::null_mut();
        }
    }
}

// SAFETY: GoSession runs genmove on WorkerThreadPool (experimental-threads). Only one
// genmove runs at a time per handle; play/clear stay on the main thread around it.
unsafe impl Send for NativeKataGo {}
unsafe impl Sync for NativeKataGo {}

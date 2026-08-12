use std::{time::Duration, usize};

unsafe extern "C" {
    fn cargokit_cpp_runtime_probe() -> usize;
}

#[no_mangle]
pub extern "C" fn sum(a: usize, b: usize) -> usize {
    a + b
}

#[no_mangle]
pub extern "C" fn sum_long_running(a: usize, b: usize) -> usize {
    std::thread::sleep(Duration::from_secs(5));
    a + b
}

#[no_mangle]
pub extern "C" fn cpp_runtime_probe() -> usize {
    unsafe { cargokit_cpp_runtime_probe() }
}

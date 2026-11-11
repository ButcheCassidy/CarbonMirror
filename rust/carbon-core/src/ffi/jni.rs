//! JNI bridge for the forked scrcpy server (`com.genymobile.scrcpy.carbon.CarbonCore`). The phone runs the
//! same TLS code as the Mac. Return values: `>= 0` success (a count or handle), `< 0` the negated
//! [`CmStatus`] code. Java byte arrays are copied in and out with bounds checks.

use jni::JNIEnv;
use jni::objects::{JByteArray, JClass};
use jni::sys::{jboolean, jint, jlong, JNI_FALSE, JNI_TRUE};

use super::{CmTlsIdentity, CmTlsSession, MAX_BUFFER_LEN};
use crate::crypto;
use crate::status::{CmResult, CmStatus};
use crate::tls::{Identity, Session};

fn fail(e: CmStatus) -> jint {
    -e.code()
}

fn result(r: CmResult<usize>) -> jint {
    match r {
        Ok(n) => jint::try_from(n).unwrap_or(jint::MAX),
        Err(e) => fail(e),
    }
}

/// Copies `len` bytes at `off` out of a Java array.
fn read_region(env: &JNIEnv, array: &JByteArray, off: jint, len: jint) -> CmResult<Vec<u8>> {
    let total = env.get_array_length(array).map_err(|_| CmStatus::NullPointer)?;
    let len_u = usize::try_from(len).map_err(|_| CmStatus::InvalidArgument)?;
    if off < 0 || len_u > MAX_BUFFER_LEN || off.checked_add(len).is_none_or(|end| end > total) {
        return Err(CmStatus::InvalidArgument);
    }
    let mut buf = vec![0i8; len_u];
    env.get_byte_array_region(array, off, &mut buf).map_err(|_| CmStatus::InvalidArgument)?;
    Ok(buf.into_iter().map(|b| b as u8).collect())
}

/// Copies `data` into a Java array at `off` (the caller checked the room).
fn write_region(env: &JNIEnv, array: &JByteArray, off: jint, data: &[u8]) -> CmResult<()> {
    let signed: Vec<i8> = data.iter().map(|&b| b as i8).collect();
    env.set_byte_array_region(array, off, &signed).map_err(|_| CmStatus::InvalidArgument)
}

/// Room left in a Java array after `off`, capped by `len`.
fn room(env: &JNIEnv, array: &JByteArray, off: jint, len: jint) -> CmResult<usize> {
    let total = env.get_array_length(array).map_err(|_| CmStatus::NullPointer)?;
    if off < 0 || len < 0 || off.checked_add(len).is_none_or(|end| end > total) {
        return Err(CmStatus::InvalidArgument);
    }
    usize::try_from(len).map_err(|_| CmStatus::InvalidArgument).map(|n| n.min(MAX_BUFFER_LEN))
}

/// # Safety
/// `handle` is 0 or a live `CmTlsSession` pointer created by `sessionNew` and not yet freed.
unsafe fn session<'a>(handle: jlong) -> CmResult<&'a mut Session> {
    // SAFETY: caller contract.
    Ok(&mut unsafe { (handle as *mut CmTlsSession).as_mut() }.ok_or(CmStatus::NullPointer)?.0)
}

/// # Safety
/// `handle` is 0 or a live `CmTlsIdentity` pointer created by `serverIdentityNew` and not yet freed.
unsafe fn identity<'a>(handle: jlong) -> CmResult<&'a Identity> {
    // SAFETY: caller contract.
    Ok(&unsafe { (handle as *const CmTlsIdentity).as_ref() }.ok_or(CmStatus::NullPointer)?.0)
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_genymobile_scrcpy_carbon_CarbonCore_abiVersion(_env: JNIEnv, _class: JClass) -> jint {
    crate::ABI_VERSION as jint
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_genymobile_scrcpy_carbon_CarbonCore_serverIdentityNew(env: JNIEnv, _class: JClass, mac_ca: JByteArray) -> jlong {
    let made = env
        .get_array_length(&mac_ca)
        .map_err(|_| CmStatus::NullPointer)
        .and_then(|len| read_region(&env, &mac_ca, 0, len))
        .and_then(|der| Identity::server(&der));
    match made {
        Ok(id) => Box::into_raw(Box::new(CmTlsIdentity(id))) as jlong,
        Err(e) => jlong::from(fail(e)),
    }
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_genymobile_scrcpy_carbon_CarbonCore_identityPin(env: JNIEnv, _class: JClass, handle: jlong, out: JByteArray) -> jint {
    // SAFETY: Java passes only handles returned by `serverIdentityNew`.
    let r = unsafe { identity(handle) }
        .and_then(|id| id.spki_hash().ok_or(CmStatus::InvalidArgument))
        .and_then(|hash| room(&env, &out, 0, crypto::SHA256_LEN as jint).and_then(|_| write_region(&env, &out, 0, &hash)))
        .map(|_| crypto::SHA256_LEN);
    result(r)
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_genymobile_scrcpy_carbon_CarbonCore_identityFree(_env: JNIEnv, _class: JClass, handle: jlong) {
    if handle > 0 {
        // SAFETY: Java frees each identity handle exactly once.
        drop(unsafe { Box::from_raw(handle as *mut CmTlsIdentity) });
    }
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_genymobile_scrcpy_carbon_CarbonCore_sessionNew(_env: JNIEnv, _class: JClass, identity_handle: jlong) -> jlong {
    // SAFETY: Java passes only handles returned by `serverIdentityNew`.
    match unsafe { identity(identity_handle) }.and_then(Session::new) {
        Ok(s) => Box::into_raw(Box::new(CmTlsSession(s))) as jlong,
        Err(e) => jlong::from(fail(e)),
    }
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_genymobile_scrcpy_carbon_CarbonCore_readTls(env: JNIEnv, _class: JClass, handle: jlong, buf: JByteArray, off: jint, len: jint) -> jint {
    // SAFETY: Java passes only live session handles.
    let r = read_region(&env, &buf, off, len).and_then(|data| unsafe { session(handle) }?.read_tls(&data)).map(|_| 0);
    result(r)
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_genymobile_scrcpy_carbon_CarbonCore_writeTls(env: JNIEnv, _class: JClass, handle: jlong, out: JByteArray, off: jint, len: jint) -> jint {
    let r = room(&env, &out, off, len).and_then(|cap| {
        let mut tmp = vec![0u8; cap];
        // SAFETY: Java passes only live session handles.
        let n = unsafe { session(handle) }?.write_tls(&mut tmp)?;
        write_region(&env, &out, off, &tmp[..n]).map(|_| n)
    });
    result(r)
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_genymobile_scrcpy_carbon_CarbonCore_readPlain(env: JNIEnv, _class: JClass, handle: jlong, out: JByteArray, off: jint, len: jint) -> jint {
    let r = room(&env, &out, off, len).and_then(|cap| {
        let mut tmp = vec![0u8; cap];
        // SAFETY: Java passes only live session handles.
        let n = unsafe { session(handle) }?.read_plain(&mut tmp)?;
        write_region(&env, &out, off, &tmp[..n]).map(|_| n)
    });
    result(r)
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_genymobile_scrcpy_carbon_CarbonCore_writePlain(env: JNIEnv, _class: JClass, handle: jlong, buf: JByteArray, off: jint, len: jint) -> jint {
    // SAFETY: Java passes only live session handles.
    let r = read_region(&env, &buf, off, len).and_then(|data| unsafe { session(handle) }?.write_plain(&data));
    result(r)
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_genymobile_scrcpy_carbon_CarbonCore_status(_env: JNIEnv, _class: JClass, handle: jlong) -> jint {
    // SAFETY: Java passes only live session handles.
    result(unsafe { session(handle) }.map(|s| s.status() as usize))
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_genymobile_scrcpy_carbon_CarbonCore_negotiated(_env: JNIEnv, _class: JClass, handle: jlong) -> jint {
    // SAFETY: Java passes only live session handles.
    let r = unsafe { session(handle) }.and_then(|s| s.negotiated()).map(|(suite, group)| (usize::from(suite) << 16) | usize::from(group));
    result(r)
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_genymobile_scrcpy_carbon_CarbonCore_close(_env: JNIEnv, _class: JClass, handle: jlong) -> jint {
    // SAFETY: Java passes only live session handles.
    result(unsafe { session(handle) }.map(|s| {
        s.close();
        0
    }))
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_genymobile_scrcpy_carbon_CarbonCore_sessionFree(_env: JNIEnv, _class: JClass, handle: jlong) {
    if handle > 0 {
        // SAFETY: Java frees each session handle exactly once.
        drop(unsafe { Box::from_raw(handle as *mut CmTlsSession) });
    }
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_genymobile_scrcpy_carbon_CarbonCore_sha256(env: JNIEnv, _class: JClass, data: JByteArray, out: JByteArray) -> jint {
    let r = env
        .get_array_length(&data)
        .map_err(|_| CmStatus::NullPointer)
        .and_then(|len| read_region(&env, &data, 0, len))
        .and_then(|bytes| room(&env, &out, 0, crypto::SHA256_LEN as jint).and_then(|_| write_region(&env, &out, 0, &crypto::sha256(&bytes))))
        .map(|_| crypto::SHA256_LEN);
    result(r)
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_genymobile_scrcpy_carbon_CarbonCore_constantTimeEquals(env: JNIEnv, _class: JClass, a: JByteArray, b: JByteArray) -> jboolean {
    let read = |x: &JByteArray| env.get_array_length(x).map_err(|_| CmStatus::NullPointer).and_then(|len| read_region(&env, x, 0, len));
    match (read(&a), read(&b)) {
        (Ok(x), Ok(y)) if crypto::constant_time_eq(&x, &y) => JNI_TRUE,
        _ => JNI_FALSE,
    }
}

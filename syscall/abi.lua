-- This simply returns ABI information
-- Makes it easier to substitute for non-ffi solution, eg to run tests

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local ffi = require "ffi"

local function inlibc_fn(k) return ffi.C[k] end

local abi = {
  arch = ffi.arch, -- ppc, x86, arm, x64, mips
  abi32 = ffi.abi("32bit"), -- boolean
  abi64 = ffi.abi("64bit"), -- boolean
  le = ffi.abi("le"), -- boolean
  be = ffi.abi("be"), -- boolean
  os = ffi.os:lower(), -- bsd, osx, linux
}

-- Makes no difference to us I believe
if abi.arch == "ppcspe" then abi.arch = "ppc" end

if abi.arch == "arm" and not ffi.abi("eabi") then error("only support eabi for arm") end

if abi.arch == "mips" then abi.mipsabi = "o32" end -- only one supported now

if abi.os == "bsd" or abi.os == "osx" then abi.bsd = true end -- some shared BSD functionality

-- Xen generally behaves like NetBSD, but our tests need to do rump-like setup; bit of a hack
ffi.cdef[[
  int __ljsyscall_under_xen;
]]
if pcall(inlibc_fn, "__ljsyscall_under_xen") then abi.xen = true end

-- TODO remove when move code
local function split(delimiter, text)
  if delimiter == "" then return {text} end
  if #text == 0 then return {} end
  local list = {}
  local pos = 1
  while true do
    local first, last = text:find(delimiter, pos)
    if first then
      list[#list + 1] = text:sub(pos, first - 1)
      pos = last + 1
    else
      list[#list + 1] = text:sub(pos)
      break
    end
  end
  return list
end

-- BSD detection
-- OpenBSD doesn't have sysctlbyname
-- The good news is every BSD has utsname
-- The bad news is that on FreeBSD it is a legacy version that has 32 byte unless you use __xuname
-- fortunately sysname is first so we can use this value
if not abi.xen and abi.os == "bsd" then
  ffi.cdef [[
  struct utsname {
  char    sysname[256];
  char    nodename[256];
  char    release[256];
  char    version[256];
  char    machine[256];
  };
  int uname(struct utsname *);
  ]]
  local ubuf = ffi.new("struct utsname")
  ffi.C.uname(ubuf)
  abi.os = ffi.string(ubuf.sysname):lower()

  -- TODO move these to their OS files

  -- openbsd ABI version
  if abi.os == "openbsd" then
    abi.openbsd = tonumber(ffi.string(ubuf.release))
  end

  -- FreeBSD ABI version
  if abi.os == "freebsd" then
    ffi.cdef [[
    int sysctlbyname(const char *sname, void *oldp, size_t *oldlenp, const void *newp, size_t newlen);
    ]]
    local buf = ffi.new("int[1]")
    local lenp = ffi.new("unsigned long[1]", ffi.sizeof("int"))
    local ok = ffi.C.sysctlbyname("kern.osreldate", buf, lenp, nil, 0)
    if ok ~= 0 then error("canot identify FreeBSD version") end
    local vs = tostring(buf[0])
    abi.freebsd = tonumber(vs:sub(1, #vs - 5)) -- major version ie 9, 10
  end

  -- NetBSD ABI version
  if abi.os == "netbsd" then
    local r = split(ubuf.release, ".")
    local maj, min = tonumber(r[1]), tonumber(r[2])
    if min == 99 then maj = maj + 1 end
    abi.netbsd = maj
  end
end

-- rump params
abi.host = abi.os -- real OS, used for rump at present may change this
abi.types = "netbsd" -- you can set to linux, or monkeypatch (see tests) to use Linux types

return abi


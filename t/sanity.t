# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket;
use Cwd qw(cwd);

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 9);

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
    lua_package_cpath "/usr/local/openresty-debug/lualib/?.so;/usr/local/openresty/lualib/?.so;;";
};

$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';

#no_long_string();

log_level('debug');

run_tests();

__DATA__

=== TEST 1: sanity
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local ck = require "resty.cookie"
            local cookie, err = ck:new()
            if not cookie then
                ngx.log(ngx.ERR, err)
                return
            end

            local fields = cookie:get_all()

            local keys = {}
            for key in pairs(fields) do
                table.insert(keys, key)
            end
            table.sort(keys)

            for _, key in ipairs(keys) do
                ngx.say(key, " => ", fields[key])
            end
        ';
    }
--- request
GET /t
--- more_headers
Cookie: SID=31d4d96e407aad42; lang=en-US
--- no_error_log
[error]
--- response_body
SID => 31d4d96e407aad42
lang => en-US

=== TEST 2: sanity 2
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local ck = require "resty.cookie"
            local cookie, err = ck:new()
            if not cookie then
                ngx.log(ngx.ERR, err)
                return
            end

            local field = cookie:get("lang")
            ngx.say("lang", " => ", field)
        ';
    }
--- request
GET /t
--- more_headers
Cookie: SID=31d4d96e407aad42; lang=en-US
--- no_error_log
[error]
--- response_body
lang => en-US



=== TEST 3: no cookie header
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local ck = require "resty.cookie"
            local cookie, err = ck:new()
            if not cookie then
                ngx.log(ngx.ERR, err)
                ngx.say(err)
                return
            end

            local field, err = cookie:get("lang")
            if not field then
                ngx.log(ngx.ERR, err)
                ngx.say(err)
                return
            end
            ngx.say("lang", " => ", field)
        ';
    }
--- request
GET /t
--- error_log
no cookie found in the current request
--- response_body
no cookie found in the current request



=== TEST 4: empty value
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local ck = require "resty.cookie"
            local cookie, err = ck:new()
            if not cookie then
                ngx.log(ngx.ERR, err)
                return
            end

            local fields = cookie:get_all()

            for k, v in pairs(fields) do
                ngx.say(k, " => ", v)
            end
        ';
    }
--- request
GET /t
--- more_headers
Cookie: SID=
--- no_error_log
[error]
--- response_body
SID => 



=== TEST 5: cookie with space/tab
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local ck = require "resty.cookie"
            local cookie, err = ck:new()
            if not cookie then
                ngx.log(ngx.ERR, err)
                return
            end

            local fields = cookie:get_all()

            for k, v in pairs(fields) do
                ngx.say(k, " => ", v)
            end
        ';
    }
--- request
GET /t
--- more_headers eval: "Cookie:  SID=foo\t"
--- no_error_log
[error]
--- response_body
SID => foo



=== TEST 6: set cookie
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local ck = require "resty.cookie"
            local cookie, err = ck:new()
            if not cookie then
                ngx.log(ngx.ERR, err)
                return
            end

            local ok, err = cookie:set({
                key = "Name", value = "Bob", path = "/",
                domain = "example.com", secure = true, httponly = true,
                expires = "Wed, 09 Jun 2021 10:18:14 GMT", max_age = 50,
                samesite = "Strict", partitioned = true, extension = "a4334aebaec"
            })
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.say("Set cookie")
        ';
    }
--- request
GET /t
--- no_error_log
[error]
--- response_headers
Set-Cookie: Name=Bob; Expires=Wed, 09 Jun 2021 10:18:14 GMT; Max-Age=50; Domain=example.com; Path=/; Secure; HttpOnly; SameSite=Strict; Partitioned; a4334aebaec
--- response_body
Set cookie



=== TEST 7: set multiple cookie
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local ck = require "resty.cookie"
            local cookie, err = ck:new()
            if not cookie then
                ngx.log(ngx.ERR, err)
                return
            end

            local ok, err = cookie:set({
                key = "Name", value = "Bob", path = "/",
            })
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            local ok, err = cookie:set({
                key = "Age", value = "20",
            })
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            local ok, err = cookie:set({
                key = "ID", value = "0xf7898",
                expires = "Wed, 09 Jun 2021 10:18:14 GMT"
            })
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.say("Set cookie")
        ';
    }
--- request
GET /t
--- no_error_log
[error]
--- comment
because "--- response_headers" does not work with multiple headers with the same
key, so use "--- raw_response_headers_like" instead
--- raw_response_headers_like: Set-Cookie: Name=Bob; Path=/\r\nSet-Cookie: Age=20\r\nSet-Cookie: ID=0xf7898; Expires=Wed, 09 Jun 2021 10:18:14 GMT
--- response_body
Set cookie



=== TEST 8: remove duplicated cookies in cookie:set
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local ck = require "resty.cookie"
            local cookie, err = ck:new()
            if not cookie then
                ngx.log(ngx.ERR, err)
                return
            end

            local ok, err = cookie:set({
                key = "Name", value = "Bob", path = "/",
            })
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            local ok, err = cookie:set({
                key = "Age", value = "20",
            })
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            local ok, err = cookie:set({
                key = "Name", value = "Bob", path = "/",
            })
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            ngx.say("Set cookie")
        ';
    }
--- request
GET /t
--- no_error_log
[error]
--- raw_response_headers_like: Set-Cookie: Name=Bob; Path=/\r\nSet-Cookie: Age=20\r\n
--- raw_response_headers_unlike: Set-Cookie: Name=Bob; Path=/\r\nSet-Cookie: Age=20\r\nSet-Cookie: Name=Bob; Path=/
--- response_body
Set cookie


=== TEST 9: set cookie with invalid SameSite attribute
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local ck = require "resty.cookie"
            local cookie, err = ck:new()
            if not cookie then
                ngx.log(ngx.ERR, err)
                return
            end

            local ok, err = cookie:set({
                key = "Name", value = "Bob", path = "/",
                domain = "example.com", secure = true, httponly = true,
                expires = "Wed, 09 Jun 2021 10:18:14 GMT", max_age = 50,
                samesite = "blahblah", extension = "a4334aebaec"
            })
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.say("Set cookie")
        ';
    }
--- request
GET /t
--- no_error_log
[error]
--- error_log
SameSite value must be 'Strict', 'Lax' or 'None'
--- response_headers
Set-Cookie: Name=Bob; Expires=Wed, 09 Jun 2021 10:18:14 GMT; Max-Age=50; Domain=example.com; Path=/; Secure; HttpOnly; a4334aebaec
--- response_body
Set cookie


=== TEST 10: set cookie with None as a valid SameSite attribute
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local ck = require "resty.cookie"
            local cookie, err = ck:new()
            if not cookie then
                ngx.log(ngx.ERR, err)
                return
            end

            local ok, err = cookie:set({
                key = "Name", value = "Bob", path = "/",
                domain = "example.com", secure = true, httponly = true,
                expires = "Wed, 09 Jun 2021 10:18:14 GMT", max_age = 50,
                samesite = "None", extension = "a4334aebaec"
            })
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.say("Set cookie")
        ';
    }
--- request
GET /t
--- no_error_log
[error]
--- response_headers
Set-Cookie: Name=Bob; Expires=Wed, 09 Jun 2021 10:18:14 GMT; Max-Age=50; Domain=example.com; Path=/; Secure; HttpOnly; SameSite=None; a4334aebaec
--- response_body
Set cookie

=== TEST 11: Cookie size
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local ck = require "resty.cookie"
            local cookie, err = ck:new()
            if not cookie then
                ngx.log(ngx.ERR, err)
                return
            end

            local size = cookie:get_cookie_size()
            ngx.say("size", " => ", size)
        ';
    }
--- request
GET /t
--- more_headers
Cookie: SID=31d4d96e407aad42; lang=en-US
--- no_error_log
[error]
--- response_body
size => 32



=== TEST 12: no cookie header
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local ck = require "resty.cookie"
            local cookie, err = ck:new()
            if not cookie then
                ngx.log(ngx.ERR, err)
                ngx.say(err)
                return
            end

            local size = cookie:get_cookie_size()
            ngx.say("size", " => ", size)
        ';
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
size => 0



=== TEST 13: get_cookie_string
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local ck = require "resty.cookie"
            local cookie, err = ck.get_cookie_string({
                key = "Name", value = "Bob", path = "/",
                domain = "example.com", secure = true, httponly = true,
                expires = "Wed, 09 Jun 2021 10:18:14 GMT", max_age = 50,
                samesite = "None", extension = "a4334aebaec"
            })
            if not cookie then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.say("Cookie string: " .. cookie)
        ';
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
Cookie string: Name=Bob; Expires=Wed, 09 Jun 2021 10:18:14 GMT; Max-Age=50; Domain=example.com; Path=/; Secure; HttpOnly; SameSite=None; a4334aebaec



=== TEST 14: set partioned to false
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local ck = require "resty.cookie"
            local cookie, err = ck:new()
            if not cookie then
                ngx.log(ngx.ERR, err)
                return
            end

            local ok, err = cookie:set({
                key = "Name", value = "Bob", path = "/",
                domain = "example.com", secure = true, httponly = true,
                expires = "Wed, 09 Jun 2021 10:18:14 GMT", max_age = 50,
                samesite = "Strict", partitioned = false, extension = "a4334aebaec"
            })
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.say("Set cookie")
        ';
    }
--- request
GET /t
--- no_error_log
[error]
--- response_headers
Set-Cookie: Name=Bob; Expires=Wed, 09 Jun 2021 10:18:14 GMT; Max-Age=50; Domain=example.com; Path=/; Secure; HttpOnly; SameSite=Strict; a4334aebaec
--- response_body
Set cookie



=== TEST 15: partioned not set
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local ck = require "resty.cookie"
            local cookie, err = ck:new()
            if not cookie then
                ngx.log(ngx.ERR, err)
                return
            end

            local ok, err = cookie:set({
                key = "Name", value = "Bob", path = "/",
                domain = "example.com", secure = true, httponly = true,
                expires = "Wed, 09 Jun 2021 10:18:14 GMT", max_age = 50,
                samesite = "Strict", extension = "a4334aebaec"
            })
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.say("Set cookie")
        ';
    }
--- request
GET /t
--- no_error_log
[error]
--- response_headers
Set-Cookie: Name=Bob; Expires=Wed, 09 Jun 2021 10:18:14 GMT; Max-Age=50; Domain=example.com; Path=/; Secure; HttpOnly; SameSite=Strict; a4334aebaec
--- response_body
Set cookie



=== TEST 16: multiple values with the same key provided
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local ck = require "resty.cookie"
            local cookie, err = ck:new()
            if not cookie then
                ngx.log(ngx.ERR, err)
                return
            end

            local fields = cookie:get_all_for("lang")
            for _, value in pairs(fields) do
                ngx.say("lang", " => ", value)
            end
        ';
    }
--- request
GET /t
--- more_headers
Cookie: SID=31d4d96e407aad42; lang=en-US; lang=en-GB;
--- no_error_log
[error]
--- response_body
lang => en-US
lang => en-GB



=== TEST 17: last cookie value is returned when multiple values with the same key provided
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local ck = require "resty.cookie"
            local cookie, err = ck:new()
            if not cookie then
                ngx.log(ngx.ERR, err)
                return
            end

            local field = cookie:get("lang")
            ngx.say("lang", " => ", field)
        ';
    }
--- request
GET /t
--- more_headers
Cookie: SID=31d4d96e407aad42; lang=en-US; lang=en-GB;
--- no_error_log
[error]
--- response_body
lang => en-GB



=== TEST 18: cookie table with last values are returned
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local ck = require "resty.cookie"
            local cookie, err = ck:new()
            if not cookie then
                ngx.log(ngx.ERR, err)
                return
            end

            local fields = cookie:get_all()

            local keys = {}
            for key in pairs(fields) do
                table.insert(keys, key)
            end
            table.sort(keys)

            for _, key in ipairs(keys) do
                ngx.say(key, " => ", fields[key])
            end
        ';
    }
--- request
GET /t
--- more_headers
Cookie: SID=31d4d96e407aad42; lang=en-US; lang=en-GB;
--- no_error_log
[error]
--- response_body
SID => 31d4d96e407aad42
lang => en-GB


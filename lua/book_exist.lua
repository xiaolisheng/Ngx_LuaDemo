local redis = require("resty.redis")
local com = require("common")
local null = ngx.null
local log = ngx.log
local ERR = ngx.ERR
local D = ngx.DEBUG


local red = redis:new()
red:set_timeout(1000) -- 1 sec
local res,err = red:connect(com.db_host,com.db_port)
if not res then
	log(E,err)
end

local key = "book_" .. ngx.var.param
local value = red:exists(key)
red:set_keepalive(100000)
log(D,key.."\n")
log(D,tostring(value).."\n")
ngx.print(value)
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

local prefix = com.filepre
local file_map_key = ngx.var.key
local file_map_value = red:hget("file_map",file_map_key)
red:set_keepalive(100000)
log(D,file_map_key.."\n")
log(D,tostring(file_map_value).."\n")
if not file_map_value or file_map_value == null then
	ngx.exit(404) 
else
	ngx.exec(prefix .. file_map_value)
end
local json = require "cjson"
local http = require "resty.http"
local redis = require "resty.redis"
local com = require "common"
local httpc =http.new()
local log = ngx.log
local E = ngx.ERR
local D = ngx.DEBUG
local spawn = ngx.thread.spawn
local wait = ngx.thread.wait
local DICT = ngx.shared.DICT
local null = ngx.null


--找出需要更新的书籍
local books = com.check_version(ngx.var.arg_teacher_id)

if not books then
    return 
end
if #books ==0 then
    ngx.say("已是最新数据")
end

local files = com.getfiles(books)

--启动下载器
com.downbook(files)



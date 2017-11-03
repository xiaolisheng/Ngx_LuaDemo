local json = require "cjson"
local http = require "resty.http"
local redis = require "resty.redis"
local log = ngx.log
local E = ngx.ERR
local D = ngx.DEBUG
local spawn = ngx.thread.spawn
local wait = ngx.thread.wait
local DICT = ngx.shared.DICT
local null = ngx.null

local _M = {
	version = 0.01,
	db_host	= "127.0.0.1",
	db_port = 6379,
	filepre = "/platform_intf/bookcdndata/",--课堂互动路径前缀
	cdnfilepre = "/classroom/uploadfile/",--cdn路径前缀
	osfilepre = "/usr/server/openresty/nginx/html/file/", --磁盘路径前缀
	uploadpre = "/usr/server/openresty/nginx/html/file/platform_intf/" --上传文件存储前缀
}

function _M.downbook(files)
    
    ngx.update_time()
    local start = ngx.now()
    local spawn = ngx.thread.spawn
    local wait = ngx.thread.wait
    local DICT = ngx.shared.DICT
    local coros = {}
    DICT:set("count",0)
    DICT:set("fails",0)

    for i=1,10,1 do
        local co = spawn(function()
            local red = redis:new()
            red:set_timeout(1000)
            local ok,err = red:connect(_M.db_host,_M.db_port)
            if not ok then
                log(E,err)
            end

            while #files>0 do
                repeat
                    --获取savepath
                    local file = table.remove(files)
                    local httpc = http.new()
                    local res,err = httpc:request_uri("http://dbs.qimonjy.cn:9012/platform_intf/qimon/v1/classroom/file/queryresurl.do", {  
                        method = "POST",  
                        body = "id="..file.id,
                        headers = {
                            ["Content-Type"] = "application/x-www-form-urlencoded"
                        }  
                    })
                    httpc:set_keepalive(100000)
                    if not res then
                        log(E,err)
                        table.insert(files,file)
                        break
                    end
                    
                    local obj = json.decode(res.body)
                    if obj.code == 1 then
                        --下载文件
                        DICT:set("count",DICT:get("count")+1)

                        local osfilepre = _M.osfilepre
                        local cdnfilepre = _M.cdnfilepre
                        local filepre = _M.filepre

                        --os文件夹路径
                        local file_parent = osfilepre .. filepre .. file.t_bookid .. "/whb/"
                        --os文件路径
                        local filepath = file_parent .. file.id
                        --文件存储日期文件夹
                        local savepath = obj.data.savePath
                        --cdn路径
                        local cdnpath = savepath .. "/" .. file.id
                        
                        local httpc = http.new()
                        local url = "http://cdn.qimonjy.cn/" .. cdnfilepre ..cdnpath
                        log(D,"count:"..DICT:get("count").."->"..url.."\n")
                        local res,err = httpc:request_uri(url)
                        log(D,"status:".. tostring(res.status).."\n")
                        httpc:set_keepalive(100000)
                        if not res then
                            log(E,err)
                            table.insert(files,file)
                            break;
                        end

                        --写入文件
                        os.execute("mkdir -p "..file_parent)
                        local file1,err = io.open(filepath,"w+")
                        file1:write(res.body)
                        file1:flush()
                        file1:close()

                        --写入redis_cdn路径映射磁盘路径
                        --文件映射key
                        local file_map_key = cdnpath
                        --文件映射value
                        local file_map_value = file.t_bookid .. "/whb/" .. file.id
                        red:hset("file_map",file_map_key,file_map_value)
                    else 
                        --数据库中不存的文件
                        DICT:set("fails",DICT:get("fails")+1)
                    end
                until true
            end
        end)
        table.insert(coros,co)
    end
    for k,v in ipairs(coros) do 
        wait(v) 
    end
    ngx.update_time()
    log(E,"\n耗費:" ..(ngx.now() - start) .."\n成功:"..DICT:get("count").."\n失败:"..DICT:get("fails").."\n")
    DICT:delete("count")
    DICT:delete("fails")
end

function _M.check_version(teacher_id)
	--获取老师所有书籍
	local httpc = http.new()
	local res,err = httpc:request_uri("http://dbs.qimonjy.cn:9012/platform_intf/qimon/v3/book/tbooks.do?teacher_id="..teacher_id)
	httpc:set_keepalive(100000)
	if not res then
	    return nil,err
	end
	local books = json.decode(res.body)
	if #books == 0 then return books end

	--更新redis存储老师书本
	local red = redis:new()
	red:set_timeout(1000)
	local ok,err = red:connect(_M.db_host,_M.db_port)
	if not ok then
	    log(E,err)
	end
	red:init_pipline()
	for i,book in ipairs(books) do
	    red:hset("teacher_"..teacher_id,"book_"..book.id,1)
	end
	red:commit_pipeline()   

	--判断redis存储是否需要更新最新版本的书籍
	local final_books={}
	for k,book in ipairs(books) do
	repeat
	    local res,err = red:hget("book_"..book.id,"version")
	    if not res or res ==null then
	        table.insert(final_books,book)
	        red:hset("book_"..book.id,"version",book.version)
	        break
	    end
	    if tonumber(res) ~= book.version then
	        table.insert(final_books,book)
	        red:hset("book_"..book.id,"version",book.version)
	    end
	until true
	end
	red:keepalive(100000)
	books=final_books

	return books
end

function _M.getfiles(books)
	--开始下载书籍资源文件
	local filepre = "/usr/local/nginx/html/"

	local files = {}
	local mark = {}

	-- local temp = table.remove(books,1)
	-- books = {}
	-- table.insert(books,temp)
	local coros = {}
	for i=1,10,1 do
	    local co = spawn(function() 
	        while #books>0 do
	        repeat 
	            httpc = http.new()
	            local v= table.remove(books)
	            local rep,err = httpc:request_uri("http://cdn.qimonjy.cn/"..v.whiteurl)
	            
	            httpc:set_keepalive(100000)
	            if not rep then 
	                log(E,err)
	                table.insert(v)
	                break
	            end
	            
	            --解析json
	            local t_bookid = v.id
	            local white = json.decode(rep.body)
	            local data,engvoice,chnvoice,explainvoice,bkimgid,jid,jlocal
	            for k,v in ipairs(white.canvas) do
	                data = v.data
	                engvoice = data.engvoice
	                chnvoice = data.chnvoice
	                explainvoice = data.explainvoice
	                bkimgid = data.bkimgid
	                if engvoice and #engvoice>0 and not mark[engvoice] then 
	                    mark[engvoice] = 1
	                    local file = {id=engvoice,t_bookid=t_bookid}
	                    table.insert(files,file)
	                end
	                if chnvoice and #chnvoice>0 and not mark[chnvoice] then 
	                    mark[chnvoice] = 1
	                    local file = {id=chnvoice,t_bookid=t_bookid}
	                    table.insert(files,file)
	                end
	                if explainvoice and #explainvoice>0 and not mark[explainvoice] then 
	                    mark[explainvoice] = 1
	                    local file = {id=explainvoice,t_bookid=t_bookid}
	                    table.insert(files,file)
	                end
	                if bkimgid and #bkimgid>0 and not mark[bkimgid] then 
	                    mark[bkimgid] = 1
	                    local file = {id=bkimgid,t_bookid=t_bookid}
	                    table.insert(files,file)
	                end
	                for k1,v1 in ipairs(v.object) do
	                    jid = v1.data.jid
	                    jlocal = v1.data.jlocal
	                    if v1.type == 5 or v1.type == 1 then 
	                        if jid and #jid>0 and not mark[jid] then 
	                            mark[jid]=1
	                            local file = {id=jid,t_bookid=t_bookid}
	                            table.insert(files,file)
	                        end
	                        if jlocal and #jlocal>0 and not mark[jlocal] then 
	                            mark[jlocal] = 1
	                            local file = {id=jlocal,t_bookid=t_bookid}
	                            table.insert(files,file)
	                        end
	                    end
	                end
	            end
	        until true
	        end
	    end)
	    table.insert(coros,co)
	end
	for k,v in ipairs(coros) do 
	    wait(v) 
	end
	log(D,"文件总数："..#files.."\n")
	return files
end


return _M
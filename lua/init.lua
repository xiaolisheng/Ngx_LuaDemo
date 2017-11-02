local redis = require("resty.redis")
local com = require("common")
local log = ngx.log
local E = ngx.ERR
local D = ngx.DEBUG
local null = ngx.null
local DICT = ngx.shared.DICT

local worker_id =ngx.worker.id() 
if worker_id== 0 then	
	log(D,"I get this task ->"..worker_id.."\n")
else
	log(D,"not my task,return->"..worker_id.."\n")
	return
end

log(D,"进入init\ncommon.version="..com.version.."\n")

local time_cycle = 600; --second

function callback(premature)
	if premature then
		log(D,"premature\n")
		return 
	end 


	
	local red = redis:new()
	red:set_timeout(1000) -- 1 sec
	local res,err = red:connect(com.db_host,com.db_port)
	if not res then
		log(E,err)
	end

	local cursor = 0
	local teachers = {}
	while true do
		res,err = red:scan(cursor,"match","teacher_*")
		if not res then
			log(E,err)
			break
		end

		for i,v in ipairs(res[2]) do
			table.insert(teachers,v)
		end

		if(tonumber(res[1]) == 0) then
			break
		else
			cursor = res[1]
		end
	end

	log(D,"find "..#teachers.." teachers")
	

	for i,v in ipairs(teachers) do
		--找出需要更新的书籍
		local books = com.check_version(string.sub(v,9))

		if not books or #books ==0 then
		     log(D,v.."->无需更新\n")
		else
			for i,v in ipairs(books) do
				log(D,"更新书本"..v.id.."\n")
			end
			
			local files = com.getfiles(books)

			--启动下载器
			com.downbook(files)
		end

	end

	local ok,err =ngx.timer.at(time_cycle,callback)
	if not ok then
		log(E,"创建timer失败\n"..err)
	end
end

local ok,err =ngx.timer.at(time_cycle,callback)
if not ok then
	log(E,"创建timer失败\n"..err)
end
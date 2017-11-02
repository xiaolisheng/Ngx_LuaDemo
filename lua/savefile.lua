
local upload = require "resty.upload"
local json = require "cjson"
local com = require "common"

local chunk_size = 1024*4
local form = upload:new(chunk_size)
local file
local filelen=0
form:set_timeout(0) -- 1 sec
local formdata = {}
local isfile = false
local param_name

function get_filename(str)
    local res = ngx.re.match(str,'filename="(.+)"')
    local res1 =ngx.re.match(str,'name="(.+)"')
    if res then for k,v in ipairs(res) do ngx.log(ngx.ERR,k.."-----"..v.."\n") end end
    if res1 then for k,v in ipairs(res1) do ngx.log(ngx.ERR,k.."-----"..v.."\n") end end
    if res then 
       isfile = true
       return res[1]
   else
        isfile = false
        local res2 =ngx.re.match(res1[1],'\\\\(.+)')
        -- ngx.log(ngx.ERR,res2)
        if res2 then 
          return res2[1]
        else
          return res1[1]
        end
   end
end


local osfilepath = com.uploadpre
local i=0
local j=1
local response ={
    code = 0,
    data = '',
    msg = ''
}

-- math.randomseed(tostring(os.time()):reverse():sub(1, 7)) --设置时间种子
local filename

while true do
    local typ, res, err = form:read()
    if not typ then
        ngx.log(ngx.ERR,"failed to read: "..err)
        response.msg=err
        ngx.print(json.encode(response))
        return
    end
    -- ngx.log(ngx.ERR,"read: "..typ.."-------" ..json.encode( res))
    if typ == "header" then
        if res[1] ~= "Content-Type" then
            param_name = get_filename(res[2])
            if isfile then  
                local path = string.gsub(formdata["path"],"\\","/")
                response.data = path.."/"..param_name
                local filepath = osfilepath .. path .."/"
                os.execute("mkdir -p "..filepath)
                --filename = tostring(os.time()) .. math.random(100,1000) .. "_" .. filename
                i=i+1
                filename = filepath  .. param_name
                file,err = io.open(filename,"w+")
                if not file then
                    ngx.log(ngx.ERR,"failed to open file ")
                    response.data=err
                    ngx.print(json.encode(response))
                    return
                end
            else
            formdata[param_name] = ''
            j = j+1
        end
    end
    elseif typ == "body" then
        if isfile then
            filelen= filelen + tonumber(string.len(res))    
            file:write(res)
        else
            formdata[param_name] = formdata[param_name] .. res
        end
    elseif typ == "part_end" then
        if isfile then
            file:close()
            file = nil
            -- ngx.update_time()
            -- local start = ngx.now()
            -- local new_filename = string.sub(filename,1,-5) .. ".webp"
            -- local cmd = "/usr/server/utils/libwebp/bin/cwebp -q 80 ".. filename .." -o " .. new_filename
            -- local num = os.execute(cmd)
            -- if num then
            --     response.data = string.sub(response.data,1,-5) .. ".webp"
            -- end
            -- ngx.update_time()
            -- ngx.log(ngx.ERR,"\r\n 压缩webp耗费时间："..(ngx.now()-start))
        else
    end
    elseif typ == "eof" then
        ngx.log(ngx.ERR,json.encode(formdata))
        response.code =1
        ngx.print(json.encode(response))
        break
    else
    end
end
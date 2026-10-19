--[[
	ClientNet
	Calls a server RemoteFunction safely and (optionally) shows the server's
	reply as a toast. Returns { Ok, Message, Data }.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local ClientNet = {}

local toast: ((string, string) -> ())? = nil

function ClientNet.SetToast(fn: (string, string) -> ())
	toast = fn
end

function ClientNet.Call(name: string, showMessage: boolean, ...: any): { Ok: boolean, Message: string?, Data: any }
	local ok, result = pcall(function(...)
		return Remotes.Function(name):InvokeServer(...)
	end, ...)
	if not ok or type(result) ~= "table" then
		result = { Ok = false, Message = "Couldn't reach the server. Try again." }
	end
	if showMessage and toast and result.Message and result.Message ~= "" then
		toast(result.Message, if result.Ok then "Success" else "Error")
	end
	return result
end

return ClientNet

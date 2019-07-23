-- Aero Server
-- Crazyman32
-- July 21, 2017



local AeroServer = {
	Services = {};
	Modules  = {};
	Shared   = {};
}

local mt = {__index = AeroServer}

local servicesFolder = game:GetService("ServerStorage").Aero.Services
local modulesFolder = game:GetService("ServerStorage").Aero.Modules
local sharedFolder = game:GetService("ReplicatedStorage").Aero.Shared
local internalFolder = game:GetService("ReplicatedStorage").Aero.Internal

local remoteServices = Instance.new("Folder")
remoteServices.Name = "AeroRemoteServices"

local FastSpawn = require(internalFolder.FastSpawn)


function AeroServer:RegisterEvent(eventName)
	local event = self.Shared.Event.new()
	self._events[eventName] = event
	return event
end


function AeroServer:RegisterClientEvent(eventName)
	local event = Instance.new("RemoteEvent")
	event.Name = eventName
	event.Parent = self._remoteFolder
	self._clientEvents[eventName] = event
	return event
end


function AeroServer:FireEvent(eventName, ...)
	self._events[eventName]:Fire(...)
end


function AeroServer:FireClientEvent(eventName, client, ...)
	self._clientEvents[eventName]:FireClient(client, ...)
end


function AeroServer:FireAllClientsEvent(eventName, ...)
	self._clientEvents[eventName]:FireAllClients(...)
end


function AeroServer:ConnectEvent(eventName, func)
	return self._events[eventName]:Connect(func)
end


function AeroServer:ConnectClientEvent(eventName, func)
	return self._clientEvents[eventName].OnServerEvent:Connect(func)
end


function AeroServer:WaitForEvent(eventName)
	return self._events[eventName]:Wait()
end


function AeroServer:WaitForClientEvent(eventName)
	return self._clientEvents[eventName]:Wait()
end


function AeroServer:RegisterClientFunction(funcName, func)
	local remoteFunc = Instance.new("RemoteFunction")
	remoteFunc.Name = funcName
	remoteFunc.OnServerInvoke = function(...)
		return func(self.Client, ...)
	end
	remoteFunc.Parent = self._remoteFolder
	return remoteFunc
end


function AeroServer:WrapModule(tbl)
	assert(type(tbl) == "table", "Expected table for argument")
	tbl._events = {}
	setmetatable(tbl, mt)
	if (type(tbl.Init) == "function" and not tbl.__aeroPreventInit) then
		tbl:Init()
	end
	if (type(tbl.Start) == "function" and not tbl.__aeroPreventStart) then
		FastSpawn(tbl.Start, tbl)
	end
end


-- Setup table to load modules on demand:
local function LazyLoadSetup(tbl, folder)
	setmetatable(tbl, {
		__index = function(t, i)
			local child = folder[i]
			if (child:IsA("ModuleScript")) then
				local obj = require(child)
				if (type(obj) == "table") then
					AeroServer:WrapModule(obj)
				end
				rawset(t, i, obj)
				return obj
			elseif (child:IsA("Folder")) then
				local nestedTbl = {}
				rawset(t, i, nestedTbl)
				LazyLoadSetup(nestedTbl, child)
				return nestedTbl
			end
		end;
	})
end


-- Load service from module:
local function LoadService(module, servicesTbl)
	
	local remoteFolder = Instance.new("Folder")
	remoteFolder.Name = module.Name
	remoteFolder.Parent = remoteServices
	
	local service = require(module)
	--AeroServer.Services[module.Name] = service
	servicesTbl[module.Name] = service
	
	if (type(service.Client) ~= "table") then
		service.Client = {}
	end
	service.Client.Server = service
	
	setmetatable(service, mt)
	
	service._events = {}
	service._clientEvents = {}
	service._remoteFolder = remoteFolder
	
end


local function InitService(service)
	
	-- Initialize:
	if (type(service.Init) == "function") then
		service:Init()
	end
	
	-- Client functions:
	for funcName,func in pairs(service.Client) do
		if (type(func) == "function") then
			service:RegisterClientFunction(funcName, func)
		end
	end
	
end


local function StartService(service)

	-- Start services on separate threads:
	if (type(service.Start) == "function") then
		FastSpawn(service.Start, service)
	end

end


local function Init()
	
	-- Lazy-load server and shared modules:
	LazyLoadSetup(AeroServer.Modules, modulesFolder)
	LazyLoadSetup(AeroServer.Shared, sharedFolder)
	
	-- Load service modules:
	local function LoadAllServices(parent, servicesTbl)
		for _,child in pairs(parent:GetChildren()) do
			if (child:IsA("ModuleScript")) then
				LoadService(child, servicesTbl)
			elseif (child:IsA("Folder")) then
				local tbl = {}
				servicesTbl[child.Name] = tbl
				LoadAllServices(child, tbl)
			end
		end
	end
	LoadAllServices(servicesFolder, AeroServer.Services)
	
	-- Initialize services:
	local function InitAllServices(services)
		for _,service in pairs(services) do
			if (getmetatable(service) == mt) then
				InitService(service)
			else
				InitAllServices(service)
			end
		end
	end
	InitAllServices(AeroServer.Services)
	
	-- Start services:
	local function StartAllServices(services)
		for _,service in pairs(services) do
			if (getmetatable(service) == mt) then
				StartService(service)
			else
				StartAllServices(service)
			end
		end
	end
	StartAllServices(AeroServer.Services)
	
	-- Expose server framework to client and global scope:
	remoteServices.Parent = game:GetService("ReplicatedStorage").Aero
	_G.AeroServer = AeroServer
	
end


Init()
local http = require "resty.http"
local cjson = require "cjson"

-- Configuration (will be defined by Helm template before this script)
-- Variables AUTH_SERVICE_URL and AUTH_SERVICE_TIMEOUT
-- are expected to be defined before this script is loaded

-- Utility functions for logging
local function log_info(msg)
  kong.log.info("[custom-auth] " .. msg)
end

local function log_warn(msg)
  kong.log.warn("[custom-auth] " .. msg)
end

local function log_error(msg)
  kong.log.err("[custom-auth] " .. msg)
end

local function log_debug(msg)
  kong.log.debug("[custom-auth] " .. msg)
end

-- Main authentication function
local function call_auth_service()
  -- Get request details
  local request_path = kong.request.get_path()
  local request_method = kong.request.get_method()
  local auth_header = kong.request.get_header("Authorization")
  
  log_debug("Processing auth request for " .. request_method .. " " .. request_path)
  
  if not auth_header then
    log_warn("No Authorization header found")
    return kong.response.exit(401, {error = "Authorization header required"})
  end
  
  -- Prepare payload for auth service
  local auth_payload = {
    path = request_path,
    method = request_method,
    token = auth_header
  }
  
  log_debug("Calling auth service at: " .. AUTH_SERVICE_URL)
  
  -- Call auth service using Kong's HTTP client
  local httpc = http.new()
  httpc:set_timeout(AUTH_SERVICE_TIMEOUT)
  
  local res, err = httpc:request_uri(AUTH_SERVICE_URL, {
    method = "POST",
    body = cjson.encode(auth_payload),
    headers = {
      ["Content-Type"] = "application/json",
      ["User-Agent"] = "Kong-Custom-Auth/1.0"
    },
    ssl_verify = false
  })
  
  if not res then
    log_error("Failed to call auth service: " .. (err or "unknown error"))
    return kong.response.exit(500, {error = "Authentication service unavailable"})
  end
  
  log_debug("Auth service responded with status: " .. res.status)
  
  if res.status ~= 200 then
    log_warn("Auth service returned non-200 status: " .. res.status)
    local response_body = res.body or "{}"
    local success, parsed_body = pcall(cjson.decode, response_body)
    if success then
      return kong.response.exit(res.status, parsed_body)
    else
      return kong.response.exit(res.status, {error = "Authentication failed"})
    end
  end
  
  -- Parse response and add headers for downstream
  local success, auth_response = pcall(cjson.decode, res.body)
  if success and auth_response and auth_response.authorized then
    -- Set user context headers for downstream services
    kong.service.request.set_header("X-User-ID", auth_response.user_id or "")
    kong.service.request.set_header("X-Enterprise-ID", auth_response.enterprise_id or "")
    kong.service.request.set_header("X-Client-ID", auth_response.client_id or "")
    kong.service.request.set_header("X-Username", auth_response.username or "")
    kong.service.request.set_header("X-Roles", auth_response.roles and cjson.encode(auth_response.roles) or "")
    
    log_info("Authentication successful for user: " .. (auth_response.user_id or "unknown"))
    log_debug("User roles: " .. (auth_response.roles and cjson.encode(auth_response.roles) or "none"))
  else
    log_warn("Authentication failed - invalid response from auth service")
    return kong.response.exit(403, {error = "Access denied"})
  end
end

-- Execute the authentication function
call_auth_service()
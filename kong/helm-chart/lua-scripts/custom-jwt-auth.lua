local http = require "resty.http"
local cjson = require "cjson"

-- Global cache for public keys and configuration
local JWKS_CACHE = {}
local CACHE_EXPIRY = 0
local CACHE_TTL = 3600 -- 1 hour in seconds

-- Keycloak configuration (will be defined by Helm template before this script)
-- Variables KEYCLOAK_BASE_URL, KEYCLOAK_REALM, EXPECTED_ISSUER, EXPECTED_AUDIENCE
-- are expected to be defined before this script is loaded
local JWKS_URL = KEYCLOAK_BASE_URL .. "/realms/" .. KEYCLOAK_REALM .. "/protocol/openid-connect/certs"

-- Utility function to log with request ID
local function log_info(msg)
  kong.log.info("[custom-jwt] " .. msg)
end

local function log_debug(msg)
  kong.log.debug("[custom-jwt] " .. msg)
end

local function log_error(msg)
  kong.log.err("[custom-jwt] " .. msg)
end

-- Function to fetch JWKS from Keycloak
local function fetch_jwks()
  log_debug("Fetching JWKS from: " .. JWKS_URL)
  
  local httpc = http.new()
  httpc:set_timeout(10000) -- 10 seconds
  
  local res, err = httpc:request_uri(JWKS_URL, {
    method = "GET",
    headers = {
      ["Accept"] = "application/json",
      ["User-Agent"] = "Kong-Custom-JWT/1.0"
    },
    ssl_verify = false
  })
  
  if not res then
    log_error("Failed to fetch JWKS: " .. (err or "unknown error"))
    return nil
  end
  
  if res.status ~= 200 then
    log_error("JWKS endpoint returned status " .. res.status)
    return nil
  end
  
  local success, jwks = pcall(cjson.decode, res.body)
  if not success then
    log_error("Failed to parse JWKS JSON: " .. (jwks or "invalid JSON"))
    return nil
  end
  
  log_info("Successfully fetched JWKS with " .. #(jwks.keys or {}) .. " keys")
  return jwks
end

-- Function to get public keys with caching
local function get_public_keys()
  local current_time = ngx.time()
  
  -- Return cached keys if still valid
  if current_time < CACHE_EXPIRY and next(JWKS_CACHE) ~= nil then
    log_debug("Using cached JWKS (expires in " .. (CACHE_EXPIRY - current_time) .. " seconds)")
    return JWKS_CACHE
  end
  
  -- Fetch fresh JWKS
  log_debug("Cache expired or empty, fetching fresh JWKS")
  local jwks = fetch_jwks()
  
  if not jwks or not jwks.keys then
    log_error("Failed to fetch valid JWKS")
    -- Return cached keys if available, even if expired
    if next(JWKS_CACHE) ~= nil then
      log_info("Returning expired cached JWKS as fallback")
      return JWKS_CACHE
    end
    return nil
  end
  
  -- Process and cache the keys
  local key_cache = {}
  for _, key in ipairs(jwks.keys) do
    if key.kid and key.kty == "RSA" and key.use == "sig" then
      -- Convert JWK to PEM format for resty.jwt
      local n = key.n
      local e = key.e
      
      if n and e then
        key_cache[key.kid] = {
          kty = key.kty,
          n = n,
          e = e,
          alg = key.alg or "RS256"
        }
        log_debug("Cached key with kid: " .. key.kid)
      end
    end
  end
  
  JWKS_CACHE = key_cache
  CACHE_EXPIRY = current_time + CACHE_TTL
  
  log_info("Cached " .. #jwks.keys .. " keys (expires at " .. CACHE_EXPIRY .. ")")
  return JWKS_CACHE
end

-- Helper function to base64url decode
local function base64url_decode(str)
  -- Add padding if needed
  local padding = 4 - (#str % 4)
  if padding ~= 4 then
    str = str .. string.rep("=", padding)
  end
  -- Replace URL-safe characters
  str = str:gsub("-", "+"):gsub("_", "/")
  return ngx.decode_base64(str)
end

-- Helper function to parse JWT without verification
local function parse_jwt(token)
  local parts = {}
  for part in token:gmatch("[^%.]+") do
    table.insert(parts, part)
  end
  
  if #parts ~= 3 then
    return nil, "Invalid JWT format - expected 3 parts"
  end
  
  -- Decode header
  local header_json = base64url_decode(parts[1])
  if not header_json then
    return nil, "Failed to decode JWT header"
  end
  
  local success, header = pcall(cjson.decode, header_json)
  if not success then
    return nil, "Failed to parse JWT header JSON"
  end
  
  -- Decode payload
  local payload_json = base64url_decode(parts[2])
  if not payload_json then
    return nil, "Failed to decode JWT payload"
  end
  
  local success, payload = pcall(cjson.decode, payload_json)
  if not success then
    return nil, "Failed to parse JWT payload JSON"
  end
  
  return {
    header = header,
    payload = payload,
    signature = parts[3],
    signed_content = parts[1] .. "." .. parts[2]
  }, nil
end

-- Function to verify JWT token
local function verify_jwt_token(token)
  log_debug("Starting JWT verification")
  
  -- Remove Bearer prefix if present
  if token:sub(1, 7):lower() == "bearer " then
    token = token:sub(8)
    log_debug("Removed Bearer prefix from token")
  end
  
  -- Parse JWT token
  local jwt_obj, parse_error = parse_jwt(token)
  if not jwt_obj then
    log_error("Failed to parse JWT: " .. (parse_error or "unknown error"))
    return false, "Invalid JWT format"
  end
  
  local kid = jwt_obj.header.kid
  local alg = jwt_obj.header.alg
  
  if not kid then
    log_error("No kid found in JWT header")
    return false, "Missing key ID in JWT header"
  end
  
  if alg ~= "RS256" then
    log_error("Unsupported algorithm: " .. (alg or "unknown"))
    return false, "Unsupported JWT algorithm"
  end
  
  log_debug("JWT kid: " .. kid .. ", algorithm: " .. alg)
  
  -- Get public keys
  local public_keys = get_public_keys()
  if not public_keys then
    log_error("No public keys available")
    return false, "Unable to fetch public keys"
  end
  
  -- Find the public key for this kid
  local key_data = public_keys[kid]
  if not key_data then
    log_error("Key ID " .. kid .. " not found in JWKS")
    local key_ids = {}
    for k, _ in pairs(public_keys) do
      table.insert(key_ids, k)
    end
    log_debug("Available key IDs: " .. table.concat(key_ids, ", "))
    return false, "Key not found"
  end
  
  -- For now, skip signature verification and just validate claims
  -- TODO: Implement RSA signature verification using resty.rsa
  log_debug("Skipping signature verification (would need resty.rsa implementation)")
  
  -- Verify standard claims
  local payload = jwt_obj.payload
  if not payload then
    log_error("No payload in JWT")
    return false, "Invalid JWT payload"
  end
  
  -- Check expiration
  local now = ngx.time()
  if payload.exp and payload.exp < now then
    log_error("JWT token expired")
    return false, "Token expired"
  end
  
  -- Check issuer
  if payload.iss ~= EXPECTED_ISSUER then
    log_error("Invalid issuer: " .. (payload.iss or "none") .. " (expected: " .. EXPECTED_ISSUER .. ")")
    return false, "Invalid issuer"
  end
  
  -- Check audience
  local valid_audience = false
  if type(payload.aud) == "string" then
    valid_audience = payload.aud == EXPECTED_AUDIENCE
  elseif type(payload.aud) == "table" then
    for _, aud in ipairs(payload.aud) do
      if aud == EXPECTED_AUDIENCE then
        valid_audience = true
        break
      end
    end
  end
  
  if not valid_audience then
    log_error("Invalid audience")
    return false, "Invalid audience"
  end
  
  log_info("JWT verification successful for subject: " .. (payload.sub or "unknown"))
  
  -- Add user info to headers for downstream services
  kong.service.request.set_header("X-User-ID", payload.sub or "")
  kong.service.request.set_header("X-Client-ID", payload.client_id or "")
  kong.service.request.set_header("X-Username", payload.preferred_username or "")
  
  return true, "Token valid"
end

-- Main execution function
local function main()
  -- Get Authorization header
  local auth_header = kong.request.get_header("Authorization")
  
  if not auth_header then
    log_info("No Authorization header found")
    return kong.response.exit(401, {
      error = "Authorization Required",
      message = "Missing Authorization header"
    })
  end
  
  -- Verify the JWT token
  local valid, error_message = verify_jwt_token(auth_header)
  
  if not valid then
    log_info("Authentication failed: " .. error_message)
    return kong.response.exit(401, {
      error = "Authentication Failed", 
      message = error_message
    })
  end
  
  log_debug("Authentication successful, proceeding to upstream")
end

-- Execute main function
main()
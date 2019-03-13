var errorList = [
  { :msg => "UNKNOWN ERROR", :code => 0 },
  { :msg => "BLE ERROR", :code => -1 },
  { :msg => "BLE HOST TIMEOUT", :code => -2 },
  { :msg => "BLE SERVER TIMEOUT", :code => -3 },
  { :msg => "BLE NO DATA", :code => -4 },
  { :msg => "BLE REQUEST CANCELLED", :code => -5 },
  { :msg => "BLE QUEUE FULL", :code => -101 },
  { :msg => "BLE REQUEST TOO LARGE", :code => -102 },
  { :msg => "BLE UNKNOWN SEND ERROR", :code => -103 },
  { :msg => "BLE CONNECTION UNAVAILABLE", :code => -104 },
  { :msg => "INVALID HTTP HEADER FIELDS IN REQUEST", :code => -200 },
  { :msg => "INVALID HTTP BODY IN REQUEST", :code => -201 },
  { :msg => "INVALID HTTP METHOD IN REQUEST", :code => -202 },
  { :msg => "NETWORK REQUEST TIMED OUT", :code => -300 },
  { :msg => "INVALID HTTP BODY IN NETWORK RESPONSE", :code => -400 },
  { :msg => "INVALID HTTP HEADER FIELDS IN NETWORK RESPONSE", :code => -401 },
  { :msg => "NETWORK RESPONSE TOO LARGE", :code => -402 },
  { :msg => "NETWORK RESPONSE OUT OF MEMORY = -403", :code => -403 },

{ :msg => "Continue", :code => 100 },
{ :msg => "Switching Protocol", :code => 101 },
{ :msg => "OK", :code => 200 },
{ :msg => "Created", :code => 201 },
{ :msg => "Accepted", :code => 202 },
{ :msg => "Non-Authoritative Information", :code => 203 },
{ :msg => "No Content", :code => 204 },
{ :msg => "Reset Content", :code => 205 },
{ :msg => "Partial Content", :code => 206 },
{ :msg => "Multiple Choices", :code => 300 },
{ :msg => "Moved Permanently", :code => 301 },
{ :msg => "Found", :code => 302 },
{ :msg => "See Other", :code => 303 },
{ :msg => "Not Modified", :code => 304 },
{ :msg => "Temporary Redirect", :code => 307 },
{ :msg => "Permanent Redirect", :code => 308 },
{ :msg => "Bad Request", :code => 400 },
{ :msg => "Unauthorized", :code => 401 },
{ :msg => "Forbidden", :code => 403 },
{ :msg => "Not Found", :code => 404 },
{ :msg => "Method Not Allowed", :code => 405 },
{ :msg => "Not Acceptable", :code => 406 },
{ :msg => "Proxy Authentication Required", :code => 407 },
{ :msg => "Request Timeout", :code => 408 },
{ :msg => "Conflict", :code => 409 },
{ :msg => "Gone", :code => 410 },
{ :msg => "Length Required", :code => 411 },
{ :msg => "Precondition Failed", :code => 412 },
{ :msg => "Payload Too Large", :code => 413 },
{ :msg => "URI Too Long", :code => 414 },
{ :msg => "Unsupported Media Type", :code => 415 },
{ :msg => "Range Not Satisfiable", :code => 416 },
{ :msg => "Expectation Failed", :code => 417 },
{ :msg => "Upgrade Required", :code => 426 },
{ :msg => "Precondition Required", :code => 428 },
{ :msg => "Too Many Requests", :code => 429 },
{ :msg => "Request Header Fields Too Large", :code => 431 },
{ :msg => "Unavailable For Legal Reasons", :code => 451 },
{ :msg => "Internal Server Error", :code => 500 },
{ :msg => "Not Implemented", :code => 501 },
{ :msg => "Bad Gateway", :code => 502 },
{ :msg => "Service Unavailable", :code => 503 },
{ :msg => "Gateway Timeout", :code => 504 },
{ :msg => "HTTP Version Not Supported", :code => 505 },
{ :msg => "Network Authentication Required", :code => 511 }
];

function errorMessage(code) {
  var result = code;
  for( var i = 0; i < errorList.size(); i++ ) {
    if( errorList[i][:code] == code) {
      result = errorList[i][:msg];
      break;
    }
  }
  return result;
}

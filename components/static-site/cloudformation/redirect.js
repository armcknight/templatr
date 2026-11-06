// The redirect distribution's viewer-request function, a CloudFront Function on
// the cloudfront-js-2.0 runtime. Every request to the old domain, and to its
// www, is answered with a permanent redirect to the same path on the site, with
// the query string kept, before any origin is reached.
//
// bin/site-template puts this file into redirect.yml's FunctionCode, which is a
// `!Sub` block: ${RedirectTo} is the stack's parameter, and no other ${…} may
// appear here.

function handler(event) {
  var request = event.request;
  var query = '';
  for (var key in request.querystring) {
    query += (query ? '&' : '?') + key + (request.querystring[key].value ? '=' + request.querystring[key].value : '');
  }
  return {
    statusCode: 301,
    statusDescription: 'Moved Permanently',
    headers: { location: { value: 'https://${RedirectTo}' + request.uri + query } }
  };
}

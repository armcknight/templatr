// The distribution's viewer-request function, a CloudFront Function on the
// cloudfront-js-2.0 runtime. It runs on each request before the cache, and does
// what an S3 website endpoint would do for a public bucket: a directory's
// address with a slash, /blog/, gets its index.html, and one without, /blog,
// redirects to the one with, so that each page has one address. www.<domain>
// redirects to <domain> for the same reason.
//
// bin/site-template puts this file into site.yml's FunctionCode, which is a
// `!Sub` block: ${DomainName} is the stack's parameter, and no other ${…} may
// appear here.

function handler(event) {
  var request = event.request;
  var query = '';
  for (var key in request.querystring) {
    query += (query ? '&' : '?') + key + (request.querystring[key].value ? '=' + request.querystring[key].value : '');
  }
  function redirect(location) {
    return {
      statusCode: 301,
      statusDescription: 'Moved Permanently',
      headers: { location: { value: location + query } }
    };
  }
  var host = request.headers.host && request.headers.host.value;
  if (host && host.toLowerCase() === 'www.${DomainName}') {
    return redirect('https://${DomainName}' + request.uri);
  }
  var uri = request.uri;
  if (uri.endsWith('/')) {
    request.uri = uri + 'index.html';
  } else if (!uri.split('/').pop().includes('.')) {
    return redirect(uri + '/');
  }
  return request;
}

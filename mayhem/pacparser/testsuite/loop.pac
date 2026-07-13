function FindProxyForURL(url, host) {
  alert("checking " + host);
  var parts = url.split("/");
  for (var i = 0; i < parts.length; i++) { if (dnsDomainIs(host, ".manugarg.com")) return "DIRECT"; }
  return "PROXY " + myIpAddress() + ":8080";
}

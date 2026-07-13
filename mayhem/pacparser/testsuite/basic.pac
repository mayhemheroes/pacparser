function FindProxyForURL(url, host) {
  if (shExpMatch(host, "*.example.com")) return "DIRECT";
  if (isInNet(dnsResolve(host), "10.0.0.0", "255.0.0.0")) return "PROXY proxy.example.com:8080";
  return "PROXY fallback.example.com:3128; DIRECT";
}

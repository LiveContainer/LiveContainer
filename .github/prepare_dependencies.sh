# download openssl
curl -LO https://github.com/krzyzanowskim/OpenSSL/releases/download/3.6.5000/OpenSSL.xcframework.zip
unzip OpenSSL.xcframework.zip
rm OpenSSL.xcframework.zip
mv OpenSSL.xcframework Dependencies/OpenSSL.xcframework
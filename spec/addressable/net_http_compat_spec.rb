# frozen_string_literal: true

# Copyright (C) Bob Aman
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.


require "spec_helper"

require "addressable/uri"
require "net/http"
require "socket"

describe Net::HTTP do
  # A local server that answers one request, so the spec doesn't need the
  # network.
  around do |example|
    @server = TCPServer.new("127.0.0.1", 0)
    @request = nil
    thread = Thread.new do
      client = @server.accept
      lines = []
      while (line = client.gets) && line != "\r\n"
        lines << line.chomp
      end
      @request = lines
      client.write(
        "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n" \
        "Content-Length: 5\r\nConnection: close\r\n\r\nhello"
      )
      client.close
    end
    begin
      example.run
    ensure
      @server.close
      thread.join(5)
      thread.kill
    end
  end

  it "should be compatible with Addressable" do
    port = @server.addr[1]
    uri = Addressable::URI.parse("http://127.0.0.1:#{port}/path?q=1")
    expect(Net::HTTP.get(uri)).to eq("hello")
    # Net::HTTP only takes the path from a stdlib URI, so it sends an
    # Addressable::URI whole, as an absolute-form request target.
    expect(@request.first).to eq("GET #{uri} HTTP/1.1").or(
      eq("GET /path?q=1 HTTP/1.1")
    )
    expect(@request).to include("Host: 127.0.0.1:#{port}")
  end
end

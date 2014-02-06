require 'webrick'
require './lib/webrick-websocket'
require 'thread'

$clients = []
$mutex = Mutex.new
server = WEBrick::HTTPServer.new :Port => 5936, :DocumentRoot => './static'
server.mount("/ws", WEBrick::HTTPServlet::WebSocketServlet.with do |client|
  client.on_open do
    puts "Opened: #{client}"
    $mutex.synchronize do
      $clients.push client
      for c in $clients
        c.send "#{$clients.length - 1} entered"
      end
    end
  end

  client.on_message do |msg|
    puts "Received: #{msg} from #{$clients.index client}"
    for c in $clients
      c.send WEBrick::HTMLUtils.escape("#{$clients.index client}: #{msg}")
    end
  end

  client.on_close do
    puts "Closed: #{client}"
    $mutex.synchronize do
      idx = $clients.index client
      $clients.delete client
      for c in $clients
        c.send "#{idx} quited"
      end
    end
  end
end) # must enclosed by parenthesis, because block will owned by mount instead of .with
trap :INT do
  server.shutdown
end
server.start

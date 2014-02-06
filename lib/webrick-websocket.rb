require 'webrick'
require 'websocket'

module WEBrick
  class WebSocketAgent
    def initialize(sock, version, server)
      @sock = sock
      @version = version
      @frame = WebSocket::Frame::Incoming::Server.new(:version => @version)
      @logger = server.logger
      @started = false
      @closed = false
      @message = []
      @server = server
    end

    def start(&block)
      begin
        block.call self
        @started = true
        while @server.status == :Running
          if IO.select [@sock], nil, nil, 2
            data, addr = @sock.recvfrom(2000)
            break if data == ""
            @frame << data
            while f = @frame.next
              return if f.type == :close
              @message.push f
            end
            block.call self
          end
        end
      ensure
        @closed = true
        block.call self
      end
    end

    def send(data)
      frame = WebSocket::Frame::Outgoing::Server.new(:version => @version, :data => data, :type => :text)
      begin
        @sock.write frame
        @sock.flush
      rescue => e
        @logger.error(e)
      end
    end

    def on_open(&block)
      block.call unless @started
    end

    def on_message(&block)
      block.call @message.shift until @message.empty?
    end

    def on_close(&block)
      block.call if @started and @closed
    end
  end

  module HTTPServlet
    class WebSocketServlet < AbstractServlet
      @event_block = proc do |client| end

      def self.event_block
        @event_block
      end

      def self.with(&block)
        raise ArgumentError, "block is not given" unless block
        @event_block = block

        Class.new self do |klass|
          klass.instance_variable_set :@event_block, block
        end
      end

      def initialize server, *options
        super
      end

      def do_GET request, response
        if request.path_info == ''
          handshake = WebSocket::Handshake::Server.new
          handshake << [request.request_line, request.raw_header].join()
          handshake << "\r\n"

          if handshake.finished? and handshake.valid?
            response.status = WEBrick::HTTPStatus::RC_SWITCHING_PROTOCOLS
            lines = handshake.to_s.scan(/[^\n\r]+/)
            lines.shift
            for line in lines
              key, val = line.split(':', 2)
              response[key] = val
            end

            response.instance_variable_set(:@handshake, handshake)
            response.instance_variable_set(:@event_block, self.class.event_block)
            response.instance_variable_set(:@the_owner, @server)
            def response.send_response(socket)
              begin
                setup_header()
                @header['connection'] = 'Upgrade'
                send_header(socket)

                ws = WebSocketAgent.new socket, @handshake.version, @the_owner
                ws.start(&@event_block)
              rescue Errno::EPIPE, Errno::ECONNRESET, Errno::ENOTCONN => ex
                @logger.debug(ex)
                @keep_alive = false
              rescue Exception => ex
                @logger.error(ex)
                @keep_alive = false
              end
            end
          end
        else
          raise WEBrick::HTTPStatus::NotFound
        end
      end
    end
  end
end

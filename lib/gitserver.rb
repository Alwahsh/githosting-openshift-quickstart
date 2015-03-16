require 'java'
require File.expand_path('../netty.jar', __FILE__)

require 'logger'

java_import 'java.lang.ProcessBuilder'
java_import 'java.net.InetSocketAddress'
java_import 'java.util.concurrent.Executors'
java_import 'org.jboss.netty.bootstrap.ServerBootstrap'
java_import 'org.jboss.netty.buffer.ChannelBuffers'
java_import 'org.jboss.netty.handler.codec.http.DefaultHttpResponse'
java_import 'org.jboss.netty.handler.codec.http.HttpContentDecompressor'
java_import 'org.jboss.netty.handler.codec.http.HttpHeaders'
java_import 'org.jboss.netty.handler.codec.http.HttpChunk'
java_import 'org.jboss.netty.handler.codec.http.HttpRequest'
java_import 'org.jboss.netty.handler.codec.http.HttpRequestDecoder'
java_import 'org.jboss.netty.handler.codec.http.HttpResponseEncoder'
java_import 'org.jboss.netty.handler.codec.http.HttpResponseStatus'
java_import 'org.jboss.netty.handler.codec.http.HttpVersion'
java_import 'org.jboss.netty.handler.codec.http.QueryStringDecoder'
java_import 'org.jboss.netty.handler.logging.LoggingHandler'
java_import 'org.jboss.netty.handler.stream.ChunkedStream'
java_import 'org.jboss.netty.handler.stream.ChunkedWriteHandler'
java_import 'org.jboss.netty.channel.ChannelFutureListener'
java_import 'org.jboss.netty.channel.Channels'
java_import 'org.jboss.netty.channel.SimpleChannelUpstreamHandler'
java_import 'org.jboss.netty.channel.socket.nio.NioServerSocketChannelFactory'
java_import 'org.jboss.netty.logging.InternalLogLevel'
java_import 'org.jboss.netty.util.CharsetUtil'

class GitServer

  def initialize(config)
    @config = config
    GitServer.logger.info('Initializing server')
    @factory = NioServerSocketChannelFactory.new(Executors.new_cached_thread_pool, Executors.new_cached_thread_pool)
    @bootstrap = ServerBootstrap.new(@factory)
    @bootstrap.pipeline_factory = PipelineFactory.new
  end

  def start
    GitServer.logger.info('Starting server')
    @channel = @bootstrap.bind(InetSocketAddress.new(ENV['OPENSHIFT_DIY_IP'], Integer(ENV['OPENSHIFT_DIY_PORT'])))
  end

  def stop
    GitServer.logger.info('Stopping server')
    @channel.close
  end

  def self.logger
    @logger = Logger.new($stderr)
  end

end

class ProtocolHandler < SimpleChannelUpstreamHandler

  def channelConnected(context, event)
    GitServer.logger.debug('New connection')
  end

  def messageReceived(context, event)
    @context = context
    request = event.message
    case request
      when HttpRequest
        handle_request(request)
      when HttpChunk
        handle_chunk(request)
    end
  end

  def handle_request(request)
    @response = DefaultHttpResponse.new(HttpVersion::HTTP_1_1, HttpResponseStatus::OK)
    case
      when match = /(.*)\/info\/refs\?service=git-((upload|receive)-pack)$/.match(request.uri)
        handle_info_refs(request, match[2], match[1])
      when match = /(.*)\/git-upload-pack$/.match(request.uri)
        handle_service(request, 'upload-pack', match[1])
      when match = /(.*)\/git-receive-pack$/.match(request.uri)
        handle_service(request, 'receive-pack', match[1])
    end
  end

  def handle_info_refs(request, service, path)
    refs = `git #{service} --stateless-rpc --advertise-refs #{git_path(path)}`
    header = "# service=git-#{service}\n"
    header = (header.size + 4).to_s(16).rjust(4, '0') + header
    @response.content = ChannelBuffers.copiedBuffer("#{header}0000#{refs}", CharsetUtil::UTF_8)
    @response.set_header(HttpHeaders::Names::CONTENT_TYPE, "application/x-git-%s-advertisement" % service)
    @context.channel.write(@response).addListener(ChannelFutureListener::CLOSE)
  end

  def handle_service(request, service, path)
    @response.setHeader(HttpHeaders::Names::CONTENT_TYPE, "application/x-git-%s-result" % service)
    @process = ProcessBuilder.new("git", service, "--stateless-rpc", git_path(path)).start
    @process.output_stream.write(request.content.array)
    request_done unless request.chunked?
  end

  def handle_chunk(chunk)
    @process.output_stream.write(chunk.content.array)
    request_done if chunk.last?
  end

  def request_done
    @process.output_stream.close
    @context.channel.write(@response)
    @context.channel.write(ChunkedStream.new(@process.input_stream)).addListener(ChannelFutureListener::CLOSE)
  end

  def channelClosed(context, event)
    GitServer.logger.debug('Connection closed')
  end

  def git_path(uri)
    return nil if uri.include?('..')
    path = File.join(ENV['OPENSHIFT_DATA_DIR'], uri)
    unless File.exists?(path)
      `git init --bare #{path}`
    end
    path
  end

end

class PipelineFactory

  include org.jboss.netty.channel.ChannelPipelineFactory

  def getPipeline
    pipeline = Channels.pipeline
    #pipeline.add_last("logger", LoggingHandler.new(InternalLogLevel::INFO, false))
    pipeline.add_last("decoder", HttpRequestDecoder.new)
    pipeline.add_last("encoder", HttpResponseEncoder.new)
    pipeline.add_last("chunked_writer", ChunkedWriteHandler.new)
    pipeline.add_last("decompressor", HttpContentDecompressor.new)
    # Add execution handler?
    pipeline.add_last('handler', ProtocolHandler.new)
    pipeline
  end

end
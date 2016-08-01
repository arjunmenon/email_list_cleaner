
module Net

  class SMTP

    # Monkey Patch to ensure SMTP uses proxies if available.
    def tcp_socket(address, port)
      if proxy = EmailListCleaner.instance.next_proxy
        EmailListCleaner.instance.pg.log "  trying: #{address} - from: #{proxy}"
        return Proxifier::Proxy(proxy).open(address, port)
      else
        TCPSocket.open(address, port)
      end
    end
    
  end

end
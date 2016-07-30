
module Net

  class SMTP

    # Monkey Patch to ensure SMTP uses proxies if available.
    def tcp_socket(address, port)
      if random_proxy = EmailListCleaner.instance.random_proxy
        return Proxifier::Proxy(random_proxy).open(address, port)
      else
        TCPSocket.open(address, port)
      end
    end
    
  end

end
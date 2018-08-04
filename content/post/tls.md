+++
title = "TLS（一）"
date = 2018-08-03T07:24:15+08:00
draft = false

# Tags and categories
# For example, use `tags = []` for no tags, or the form `tags = ["A Tag", "Another Tag"]` for one or more tags.
tags = ["TLS"]
categories = ["Golang","Web","密码学"]

# Featured image
# Place your image in the `static/img/` folder and reference its filename below, e.g. `image = "example.jpg"`.
# Use `caption` to display an image caption.
#   Markdown linking is allowed, e.g. `caption = "[Image credit](http://example.org)"`.
# Set `preview` to `false` to disable the thumbnail in listings.
[header]
image = ""
caption = ""
preview = true

+++

<!--more-->

# 1. TLS 基本概念

> 传输层安全性协议（英语：Transport Layer Security，缩写作 TLS），及其前身安全套接层（Secure Sockets Layer，缩写作 SSL）是一种安全协议，目的是为互联网通信，提供安全及数据完整性保障。网景公司（Netscape）在1994年推出首版网页浏览器，网景导航者时，推出HTTPS协议，以SSL进行加密，这是SSL的起源。IETF将SSL进行标准化，1999年公布第一版TLS标准文件。随后又公布RFC 5246 （2008年8月）与 RFC 6176 （2011年3月）。在浏览器、电子邮件、即时通信、VoIP、网络传真等应用程序中，广泛支持这个协议。主要的网站，如Google、Facebook等也以这个协议来创建安全连线，发送数据。目前已成为互联网上保密通信的工业标准。

> SSL包含记录层（Record Layer）和传输层，记录层协议确定传输层数据的封装格式。传输层安全协议使用X.509认证，之后利用非对称加密演算来对通信方做身份认证，之后交换对称密钥作为会谈密钥（Session key）。这个会谈密钥是用来将通信两方交换的数据做加密，保证两个应用间通信的保密性和可靠性，使客户与服务器应用之间的通信不被攻击者窃听。

　　以上是 Wiki 对 TLS 的描述，通俗点说，TLS 就是用来在通信双方之间建立一条安全的加密的而又可靠的通道，确保双方完成数据交换。

　　本文主要是结合 Go 的 TLS(<= 1.2) 实现来分析如何一步一步搭建起这条“通道”的。在此之前，需要理解秘钥交换算法，签名算法，密码算法，密码模式，摘要算法，它们的组合称为密码套件(CipherSuite)。例如 `TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384`

- 秘钥交换算法：ECDHE，椭圆曲线秘钥交换，用于交换公钥生成预备主密钥
- 签名算法：ECDSA，椭圆曲线数字签名算法，用于身份认证
- 密码算法：AES 256，秘钥为 256-bits 的 AES 加密算法，用于对数据的加密
- 密码模式：GCM，伽罗瓦计数器模式，数据块加密的模式
- 摘要算法：SHA384，加密算法中使用的摘要算法

　　对于上述各种算法，此处就不展开细说了，Go 的标准库`crypto`以及`x/crypto`都有详细的实现，以下是 Go 实现的秘钥套件。

|套件名|可用版本|伪随机数算法|伪随机算法中的 hash|
|:---|:---:|:---:|:---:|
|TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305|1.2|prf12|SHA256|
|TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305|1.2|prf12|SHA256|
|TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256|1.2|prf12|SHA256|
|TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256|1.2|prf12|SHA256|
|TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384|1.2|prf12|SHA384|
|TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384|1.2|prf12|SHA384|
|TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA|< 1.2|prf10/prf30|MD5,SHA1|
|TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA|< 1.2|prf10/prf30|MD5,SHA1|
|TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA|< 1.2|prf10/prf30|MD5,SHA1|
|TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA|< 1.2|prf10/prf30|MD5,SHA1|
|TLS_RSA_WITH_AES_128_GCM_SHA256|1.2|prf12|SHA256|
|TLS_RSA_WITH_AES_256_GCM_SHA384|1.2|prf12|SHA384|
|TLS_RSA_WITH_AES_128_CBC_SHA|< 1.2|prf10/prf30|MD5,SHA1|
|TLS_RSA_WITH_AES_256_CBC_SHA|< 1.2|prf10/prf30|MD5,SHA1|
|TLS_ECDHE_RSA_WITH_3DES_EDE_CBC_SHA|< 1.2|prf10/prf30|MD5,SHA1|
|TLS_RSA_WITH_3DES_EDE_CBC_SHA|< 1.2|prf10/prf30|MD5,SHA1|

# 2. TLS 握手的流程图

　　以下是以RSA秘钥交换算法为基础的双向证书握手流程图，有时可以忽略客户端证书需求。
![](https://upload.wikimedia.org/wikipedia/commons/thumb/a/ae/SSL_handshake_with_two_way_authentication_with_certificates.svg/1920px-SSL_handshake_with_two_way_authentication_with_certificates.svg.png)

大致可以分为以下几步：

- 客户端生成客户端随机数，协商版本，秘钥套件等信息，发起握手（clientHelloMsg）
- 服务端收到 clientHelloMsg，同时生成服务端随机数，再同协商结果一同返回客户端（serverHelloMsg）
- 客户端收到 serverHelloMsg
- 服务端发送证书给客户端
- 申请客户端发送证书
- 客户端验证证书
- 客户端发送证书
- 服务端验证证书
- 客户端对之前所有的信息计算 hash，再以证书私钥对 hash 值进行签名，发送签名给服务端
- 服务端同样方式计算 hash ，并以客户端证书公钥对签名进行验证
- 客户端生成随机数作为预备主密钥，用服务端公钥加密，发送给服务端
- 服务端解密预备主密钥
- 客户端，服务端拥有了相同的预备主密钥，客户端随机数，服务端随机数，在此基础上，使用相同的秘钥导出算法 prf 计算得到主密钥
- 客户端以此主密钥作为后续会话的加密秘钥，转为加密模式，通知服务端切换
- 客户端结束握手
- 服务端收到切换通知，也转为加密模式
- 服务端结束握手

　　实际运用中，主密钥只是用来生成一系列秘钥的起点，两端的加密秘钥不一定相同，但是由于主密钥的存在，使得双方都知道对方使用的是哪一个秘钥，这样也提高了安全性。

# 3. Go 的 TLS 详细实现

　　首先我们假设服务端已经开启了 TLS，客户端通过拨号的方式连接服务端，在此基础上我们来分析整个 TLS 的握手流程。

## 3.1 ClientHello & ServerHello 阶段

### 3.1.1 客户端从正式发送 ClientHelloMsg 到接收 ServerHelloMsg

1. 客户端设置超时，并通过 Dial 的方式获得可用的 TCPConn，同时初始化`tls.Config`，主要是`config.ServerName`

    ```go
    timeout := dialer.Timeout

	if !dialer.Deadline.IsZero() {
		deadlineTimeout := time.Until(dialer.Deadline)
		if timeout == 0 || deadlineTimeout < timeout {
			timeout = deadlineTimeout
		}
	}

	var errChannel chan error

	// [Min] 如果有超时，在超时的时候，向 errChannel 发送一个超时信号
	// [Min] 注意，errChannel 为2个缓存的非阻塞通道，这样就不会阻塞较慢的那个 goroutine 造成泄露
	if timeout != 0 {
		errChannel = make(chan error, 2)
		time.AfterFunc(timeout, func() {
			errChannel <- timeoutError{}
		})
	}

	// [Min] 正常调用 Dial，获取底层 conn，一般为 TCPConn
	rawConn, err := dialer.Dial(network, addr)
	if err != nil {
		return nil, err
	}

	// [Min] 获取 hostname
	colonPos := strings.LastIndex(addr, ":")
	if colonPos == -1 {
		colonPos = len(addr)
	}
	hostname := addr[:colonPos]

	// [Min] 初始化 config
	if config == nil {
		config = defaultConfig()
	}
	// If no ServerName is set, infer the ServerName
	// from the hostname we're connecting to.
	// [Min] 设置 ServerName，这个很重要，因为服务端需要以此来获取证书发送给客户端
	if config.ServerName == "" {
		// Make a copy to avoid polluting argument or default.
		c := config.Clone()
		c.ServerName = hostname
		config = c
	}
    ```

2. 客户端封装 TCPConn 为 tls.Conn，并发起握手

    ```go
    	// [Min] 构造客户端的 tls.Conn
	conn := Client(rawConn, config)

	// [Min] 没有超时，直接调用 Handshake，等到 Handshake 结束
	if timeout == 0 {
		err = conn.Handshake()
	} else {
		// [Min] 有超时，发起一个 goroutine 调用 Handshake
		go func() {
			errChannel <- conn.Handshake()
		}()

		// [Min] 可能是超时返回，也可能是 Handshake 结束的返回
		err = <-errChannel
	}

    ```
    ```go
    func Client(conn net.Conn, config *Config) *Conn {
	    return &Conn{conn: conn, config: config, isClient: true}
    }
    ```

3. 客户端调用c.clientHandshake()

    ```go
    if c.isClient {
		c.handshakeErr = c.clientHandshake()
	} else {
		c.handshakeErr = c.serverHandshake()
	}
    ```

4. 客户端调用 makeClientHello 构造 clientHelloMsg

    clientHelloMsg 包含以下信息:

    > 1. 默认采用最新的版本 TLS 1.2  
    > 2. 非压缩方法  
    > 3. 要求服务端提供证书状态  
    > 4. 要求服务端提供 hs.cert.SignedCertificateTimestamps  
    > 5. serverName 为 hostnameInSNI(config.ServerName)，目前只支持 DNS hostname，如果是IP 地址，serverName会设置为空  
    > 6. 客户端支持的椭圆曲线 supportedCurves  
    > 7. 客户端支持的点 supportedPoints，目前只支持非压缩的点  
    > 8. NPN 模式，由 len(config.NextProtos) > 0 确定，让服务端发送NextProtos，客户端进行选择  
    > 9. 支持安全重协商  
    > 10. ALPN 模式，将客户端config.NextProtos发给服务端，让服务端选择  
    > 11. 客户端可以使用的密码套件  
    > 12. 客户端随机数  
    > 13. >= TLS 1.2, 客户端支持的签名算法    
    
    ```go
    // [Min] 根据config构造clientHelloMsg
	hello, err := makeClientHello(c.config)
	if err != nil {
		return err
	}
    ```

5. 检查有没有可以复用的候选 session

    > 1. 首先要支持 sessionTicket，且c.config.ClientSessionCache不能为空  
    > 2. 根据服务端 serverName 或者 IP，从c.config.ClientSessionCache中获取有相应键值的 ClientSessionState，其中包含可以恢复 session 的 ticket  
    > 3. 如果有，检查是否符合客户端的密码套件要求，是否符合 TLS 版本要求  
    > 4. 如果3都 ok，将 ClientSessionState 中的 ticket 赋值给hello.sessionTicket，并随机分配一个16字节的hello.sessionId 

    ```go
    // [Min] 开始检查复用 Session 的可能
	var session *ClientSessionState
	var cacheKey string
	// [Min] 首先获取 config 中的 ClientSessionCache，如果不支持重用，seesionCache 设置为 nil
	sessionCache := c.config.ClientSessionCache
	if c.config.SessionTicketsDisabled {
		sessionCache = nil
	}

	// [Min] 如果此时 sessionCache 不为 nil，说明可以支持重用 session，设置 hello.ticketSupported 为真
	if sessionCache != nil {
		hello.ticketSupported = true
	}

	// Session resumption is not allowed if renegotiating because
	// renegotiation is primarily used to allow a client to send a client
	// certificate, which would be skipped if session resumption occurred.
	// [Min] 只有首次握手才能重用
	if sessionCache != nil && c.handshakes == 0 {
		// Try to resume a previously negotiated TLS session, if
		// available.
		// [Min] 根据ServerName 或服务器地址获取 sessioncachekey
		cacheKey = clientSessionCacheKey(c.conn.RemoteAddr(), c.config)
		// [Min] 从 sessionCache 中获取该 session
		candidateSession, ok := sessionCache.Get(cacheKey)
		if ok {
			// Check that the ciphersuite/version used for the
			// previous session are still valid.
			// [Min] 如果找到了，再次检查该 session 使用的密码套件是否在客户端的支持列表中
			cipherSuiteOk := false
			for _, id := range hello.cipherSuites {
				if id == candidateSession.cipherSuite {
					cipherSuiteOk = true
					break
				}
			}

			// [Min] 检查该 session 使用的版本是否有效
			versOk := candidateSession.vers >= c.config.minVersion() &&
				candidateSession.vers <= c.config.maxVersion()
			if versOk && cipherSuiteOk {
				session = candidateSession
			}
		}
	}

	// [Min] 如果 session 可用，将 session.sessionTicket 赋值给 hello.sessionTicket
	if session != nil {
		hello.sessionTicket = session.sessionTicket
		// A random session ID is used to detect when the
		// server accepted the ticket and is resuming a session
		// (see RFC 5077).
		// [Min] 同时新建一个16字节的随机数作为该重用 session 的 id
		hello.sessionId = make([]byte, 16)
		if _, err := io.ReadFull(c.config.rand(), hello.sessionId); err != nil {
			return errors.New("tls: short read from Rand: " + err.Error())
		}
	}
    ```

6. 构造clientHandshakeState，并调用其handshake()

    clientHandshakeState 中包含了:

    > 1. 该tls.Conn  
    > 2. 之前构造的clientHelloMsg  
    > 3. 候选复用 ClientSessionState  
    
    ```go
    // [Min] 构造 clientHandshakeState
	hs := &clientHandshakeState{
		c:       c,       // [Min] TLS Conn
		hello:   hello,   // [Min] clientHelloMsg
		session: session, // [Min] 重用 session
	}
    ```

7. 直接发送 clientHelloMsg 到客户端（不走sendBuf），并等待读取服务端的回应 serverHelloMsg

    ```go
    // send ClientHello
	// [Min] 明文写入 clientHelloMsg，直接推送到服务端，没有走c.sendBuf
	if _, err := c.writeRecord(recordTypeHandshake, hs.hello.marshal()); err != nil {
		return err
	}

    // [Min] 读取 handshake 的返回消息，并构建对应类型的消息体实例 msg
	msg, err := c.readHandshake()
	if err != nil {
		return err
	}

	var ok bool
	// [Min] 期待返回的是 serverHelloMsg
	if hs.serverHello, ok = msg.(*serverHelloMsg); !ok {
		c.sendAlert(alertUnexpectedMessage)
		return unexpectedMessageError(hs.serverHello, msg)
	}
    ```

8. 读取到 serverHelloMsg 后，根据协商结果调用 hs.pickTLSVersion()，hs.pickCipherSuite() 设置版本，密码套件等

    ```go
    // [Min] 选择 TLS 版本，设置 hs.c.vers，hs.c.haveVers
	if err = hs.pickTLSVersion(); err != nil {
		return err
	}

	// [Min] 选择加密套件，设置 hs.c.cipherSuite
	if err = hs.pickCipherSuite(); err != nil {
		return err
	}
    ```

    ```go
    // [Min] 匹配对应的 TLS 版本，更新到 hs.c.vers，hs.c.haveVers
    func (hs *clientHandshakeState) pickTLSVersion() error {
    	vers, ok := hs.c.config.mutualVersion(hs.serverHello.vers)
    	if !ok || vers < VersionTLS10 {
    		// TLS 1.0 is the minimum version supported as a client.
    		hs.c.sendAlert(alertProtocolVersion)
    		return fmt.Errorf("tls: server selected unsupported protocol version %x", hs.serverHello.vers)
    	}

    	hs.c.vers = vers
    	hs.c.haveVers = true

    	return nil
    }    
    ```

    ```go
    // [Min] 匹配加密套件，更新 hs.c.cipherSuite
    func (hs *clientHandshakeState) pickCipherSuite() error {
    	if hs.suite = mutualCipherSuite(hs.hello.cipherSuites, hs.serverHello.cipherSuite); hs.suite == nil {
    		hs.c.sendAlert(alertHandshakeFailure)
    		return errors.New("tls: server chose an unconfigured cipher suite")
    	}

    	hs.c.cipherSuite = hs.suite.id
    	return nil
    }
    ```

9. 调用 hs.processServerHello() 对 serverHelloMsg 的其他处理与检查，得知是否重用 session

    > 1. 压缩方法检查
    > 2. 安全重协商检查
    > 3. NPN，ALPN 模式的检查
    > 4. scts 的处理
    > 5. 重用 session 的判断，此处我们只要判断serverHelloMsg中的 sessionId 是否与我们之前在 clientHelloMsg 中发送的 sessionId 相同，相同就表示可以重用之前发送的 ticket
    > 6. 如果决定重用 session 后，对重用 session 的检查

10. 客户端完成 clientHelloMsg & serverHelloMsg

    　　新建客户端的 finishedHash，当我们处理完一条消息后（包括发送完毕），用来记录所有握手阶段的消息的 hash 值，如果不是重用 session，且服务端对客户端证书有要求，我们也会将所有消息记录在 finishedHash 的 buffer 中。  
    　　完成 clientHelloMsg 和 serverHelloMsg，此后再开启缓存写入模式。

    ```go
    hs.finishedHash = newFinishedHash(c.vers, hs.suite)

	// No signatures of the handshake are needed in a resumption.
	// Otherwise, in a full handshake, if we don't have any certificates
	// configured then we will never send a CertificateVerify message and
	// thus no signatures are needed in that case either.
	if isResume || (len(c.config.Certificates) == 0 && c.config.GetClientCertificate == nil) {
		hs.finishedHash.discardHandshakeBuffer()
	}

	hs.finishedHash.Write(hs.hello.marshal())
    hs.finishedHash.Write(hs.serverHello.marshal())
    
    c.buffering = true
    ```

### 3.1.2  服务端从接收 ClientHelloMsg 到正式发送 ServerHelloMsg

1. 与客户端类似，服务端也是在获得一个可用 TCPConn 之后，对其进行封装，得到tls.Conn，此时 config 已经初始化且包含了服务端的证书

    ```go
    func (l *listener) Accept() (net.Conn, error) {
	    c, err := l.Listener.Accept()
	    if err != nil {
	    	return nil, err
	    }
	    return Server(c, l.config), nil
    }
    ```
    ```go
    func Server(conn net.Conn, config *Config) *Conn {
    	return &Conn{conn: conn, config: config}
    }   
    ```

2. 服务端发起握手

    　　在服务端为该 tls.Conn 发起的 goroutine 中，我们会判断是否为 tls.Conn，如果是，那么我们就会发起握手。

    ```go
    if tlsConn, ok := c.rwc.(*tls.Conn); ok {
		if d := c.server.ReadTimeout; d != 0 {
			c.rwc.SetReadDeadline(time.Now().Add(d))
		}
		if d := c.server.WriteTimeout; d != 0 {
			c.rwc.SetWriteDeadline(time.Now().Add(d))
		}
		if err := tlsConn.Handshake(); err != nil {
			c.server.logf("http: TLS handshake error from %s: %v", c.rwc.RemoteAddr(), err)
			return
		}
		c.tlsState = new(tls.ConnectionState)
		*c.tlsState = tlsConn.ConnectionState()
		if proto := c.tlsState.NegotiatedProtocol; validNPN(proto) {
			if fn := c.server.TLSNextProto[proto]; fn != nil {
				h := initNPNRequest{tlsConn, serverHandler{c.server}}
				fn(c.server, tlsConn, h)
			}
			return
		}
	}
    ```

3. 与客户端类似，服务端会调起 c.serverHandshake()，正式发起握手程序

    > 3.1 首先会调起 c.config.serverInit(nil)，来检查并更新用于生成 SessionTicket 的 c.sessionTicketKeys

    ```go
    // serverInit is run under c.serverInitOnce to do initialization of c. If c was
    // returned by a GetConfigForClient callback then the argument should be the
    // Config that was passed to Server, otherwise it should be nil.
    // [Min] 主要是初始化c.sessionTicketKeys
    // [Min] 如果不支持SessionTickets，或者已经有sessionTicketKeys，直接返回
    func (c *Config) serverInit(originalConfig *Config) {
    	if c.SessionTicketsDisabled || len(c.ticketKeys()) != 0 {
    		return
    	}

    	alreadySet := false
    	for _, b := range c.SessionTicketKey {
    		if b != 0 {
    			alreadySet = true
    			break
    		}
    	}

    	// [Min] 如果 SessionTicketKey 为0，需要先设置SessionTicketKey
    	// [Min] 如果 originalConfig 不是nil，拷贝 originalConfig 的SessionTicketKey
    	// [Min] 如果是nil，则随机生成32字节的SessionTicketKey
    	if !alreadySet {
    		if originalConfig != nil {
    			copy(c.SessionTicketKey[:], originalConfig.SessionTicketKey[:])
	    	} else if _, err := io.ReadFull(c.rand(), c.SessionTicketKey[:]); err != nil {
    			c.SessionTicketsDisabled = true
    			return
    		}
    	}

    	// [Min] 接下来设置sessionTicketKeys，如果originalConfig不为nil，直接拷贝 sessionTicketKeys
    	// [Min] 否则调用 ticketKeyFromBytes 将刚才随机生成的 SessionTicketKey 转为 ticketKey 存入sessionTicketKeys
    	if originalConfig != nil {
    		originalConfig.mutex.RLock()
    		c.sessionTicketKeys = originalConfig.sessionTicketKeys
    		originalConfig.mutex.RUnlock()
    	} else {
            // [Min] 对c.SessionTicketKey求SHA512，然后再按固定长度分割为 keyName，aesKey，hmacKey           
    		c.sessionTicketKeys = []ticketKey{ticketKeyFromBytes(c.SessionTicketKey)}
    	}
    }
    ```

    > 3.2 其次构造serverHandshakeState，调用hs.readClientHello()

    ```go
    hs := serverHandshakeState{
		c: c,
	}
	// [Min] 读取客户端 helloMsg，更新相关信息，同时决定是否重用 session，如果重用，
	// [Min] 那么 session 的信息就已经从 hs.clientHello.sessionTicket 中恢复到了 hs.sessionState
	isResume, err := hs.readClientHello()
	if err != nil {
		return err
	}
    ```

4. 读取客户端发来的 clientHelloMsg, 作以下处理：

    > 4.1 如果服务端配置中自定义了c.config.GetConfigForClient，那么就先执行该函数，修改配置 config

    ```go
    if c.config.GetConfigForClient != nil {
		// [Min] 根据客户端的 helloMsg 生成一个新的 config
		if newConfig, err := c.config.GetConfigForClient(hs.clientHelloInfo()); err != nil {
			c.sendAlert(alertInternalError)
			return false, err
		} else if newConfig != nil {
			// [Min] 新的 config 中
			// [Min] sessionTicketKeys 从 c.config 中拷贝
			// [Min] SessionTicketKey 如果已经设置就不变，没有设置（0），则也从 c.config 中拷贝
			newConfig.serverInitOnce.Do(func() { newConfig.serverInit(c.config) })
			c.config = newConfig
		}
	}
    ```

    > 4.2 协商 TLS 版本，检查客户端支持的椭圆曲线，点的格式，压缩方法在服务端是否支持，同时构造 ServerHelloMsg 消息实例

    ```go
    	// [Min] 根据客户端中的版本号，协商双方都可用的版本号
    	c.vers, ok = c.config.mutualVersion(hs.clientHello.vers)
    	if !ok {
    		c.sendAlert(alertProtocolVersion)
    		return false, fmt.Errorf("tls: client offered an unsupported, maximum protocol version of %x", hs.clientHello.vers)
    	}
    	c.haveVers = true

    	// [Min] 构建服务端 HelloMsg
    	hs.hello = new(serverHelloMsg)

    	supportedCurve := false
    	preferredCurves := c.config.curvePreferences()
    	// [Min] 判断客户端支持的Curve服务端是否也支持
    Curves:
    	for _, curve := range hs.clientHello.supportedCurves {
    		for _, supported := range preferredCurves {
    			if supported == curve {
    				supportedCurve = true
    				break Curves
    			}
    		}
    	}

    	// [Min] 判断客户端支持的PointFormat是否包含pointFormatUncompressed
    	// [Min] Go标准库目前只支持pointFormatUncompressed
    	supportedPointFormat := false
    	for _, pointFormat := range hs.clientHello.supportedPoints {
    		if pointFormat == pointFormatUncompressed {
    			supportedPointFormat = true
    			break
    		}
    	}
    	// [Min] 椭圆曲线算法可用
    	hs.ellipticOk = supportedCurve && supportedPointFormat

    	foundCompression := false
    	// We only support null compression, so check that the client offered it.
    	// [Min] Go 标准库只支持非压缩，所以客户端提供的压缩方法中必须含有非压缩的方法
    	// [Min] 注：Go 实现的客户端hellomsg只设置了非压缩的方法
    	for _, compression := range hs.clientHello.compressionMethods {
    		if compression == compressionNone {
    			foundCompression = true
    			break
    		}
    	}

    	// [Min] 如果压缩方法不一致，报警
    	if !foundCompression {
    		c.sendAlert(alertHandshakeFailure)
    		return false, errors.New("tls: client does not support uncompressed connections")
    	}    
    ```

    > 4.3 serverHelloMsg 中设置协商版本，生成服务端随机数

    ```go
    // [Min] 设置服务端版本号，随机数
	hs.hello.vers = c.vers
	hs.hello.random = make([]byte, 32)
	_, err = io.ReadFull(c.config.rand(), hs.hello.random)
	if err != nil {
		c.sendAlert(alertInternalError)
		return false, err
	}
    ```

    > 4.4 检查安全重协商，NPN，ALPN 等相关信息，并作出回应

    ```go
    	// [Min] 初次handshake 客户端 hello msg 中 secureRenegotiation必须为空
    	if len(hs.clientHello.secureRenegotiation) != 0 {
    		c.sendAlert(alertHandshakeFailure)
    		return false, errors.New("tls: initial handshake had non-empty renegotiation extension")
    	}

    	// [Min] 服务端的安全重协商支持标志与客户端保持一致
    	hs.hello.secureRenegotiationSupported = hs.clientHello.secureRenegotiationSupported
    	hs.hello.compressionMethod = compressionNone
    	// [Min] 将 config 中的 serverName 设置为客户端 helloMsg 中 serverName
    	if len(hs.clientHello.serverName) > 0 {
    		c.serverName = hs.clientHello.serverName
    	}

    	// [Min] 优先ALPN模式，服务器从客户端提供的protos中选择自己支持的返回，
    	// [Min] fallback表示是否因为没有匹配成功而选择了客户端提供的第一个proto
    	if len(hs.clientHello.alpnProtocols) > 0 {
    		if selectedProto, fallback := mutualProtocol(hs.clientHello.alpnProtocols, c.config.NextProtos); !fallback {
    			hs.hello.alpnProtocol = selectedProto
    			c.clientProtocol = selectedProto
    		}
    	} else {
    		// [Min] NPN 模式，服务端返回自己支持的protos，让客户端自己去选择
    		// Although sending an empty NPN extension is reasonable, Firefox has
    		// had a bug around this. Best to send nothing at all if
    		// c.config.NextProtos is empty. See
    		// https://golang.org/issue/5445.
    		if hs.clientHello.nextProtoNeg && len(c.config.NextProtos) > 0 {
    			hs.hello.nextProtoNeg = true
    			hs.hello.nextProtos = c.config.NextProtos
    		}
    	}
    ```

    > 4.5 从服务端 config 中获取符合客户端要求的证书，并按需返回scts，同时判断证书的签名算法以及解密算法

    ```go
    	// [Min] 获取最适合 clientHelloMsg 的证书
    	hs.cert, err = c.config.getCertificate(hs.clientHelloInfo())
    	if err != nil {
    		c.sendAlert(alertInternalError)
    		return false, err
    	}
    	// [Min] 如果客户端提出需要 scts，则返回 hs.cert.SignedCertificateTimestamps
    	if hs.clientHello.scts {
    		hs.hello.scts = hs.cert.SignedCertificateTimestamps
    	}

    	// [Min] 根据选择的证书，判断公钥支持的签名算法
    	if priv, ok := hs.cert.PrivateKey.(crypto.Signer); ok {
    		switch priv.Public().(type) {
    		case *ecdsa.PublicKey:
    			hs.ecdsaOk = true
    		case *rsa.PublicKey:
    			hs.rsaSignOk = true
    		default:
    			c.sendAlert(alertInternalError)
    			return false, fmt.Errorf("tls: unsupported signing key type (%T)", priv.Public())
    		}
    	}
    	// [Min] 根据选择的证书，判断公钥支持的解密算法
    	if priv, ok := hs.cert.PrivateKey.(crypto.Decrypter); ok {
    		switch priv.Public().(type) {
    		case *rsa.PublicKey:
    			hs.rsaDecryptOk = true
    		default:
    			c.sendAlert(alertInternalError)
    			return false, fmt.Errorf("tls: unsupported decryption key type (%T)", priv.Public())
    		}
    	}    
    ```

    > 4.6 判断 clientHelloMsg 中的 sessionTicket 是否可以重用，若重用，结束 readClientHello  
      　　a) 调用 decryptTicket 对 sessionTicket 进行解密获得 hs.sessionState，sessionTicket 格式为：keyName + iv + 加密的序列化流 + HMAC(SHA256)  
    　　　　a.1) 解密的时候首先根据 keyName 从 config 的 sessionTicketKeys 中找到用于生成此 ticket 的 key    
    　　　　a.2) 然后扣去 HMAC，用 key.hmacKey 计算 HMAC，验证完整性  
    　　　　a.3) 再利用iv,key.aesKey采取 CTR 模式对加密部分解密得到明文的序列化流  
    　　　　a.4) 再反序列化明文即得到 sessionState  
      　　b) 检查 sessionState 中的版本，密码套件，证书是否符合双方要求

    ```go
    // checkForResumption reports whether we should perform resumption on this connection.
    // [Min] 根据客户端提供的 sessionTicket，检查是否重用 session
    func (hs *serverHandshakeState) checkForResumption() bool {
    	c := hs.c

    	// [Min] 首先 SessionTicketsDisabled 不能为禁用
    	if c.config.SessionTicketsDisabled {
    		return false
    	}

    	var ok bool
    	// [Min] 拷贝客户端 helloMsg 中的 sessionTicket
    	var sessionTicket = append([]uint8{}, hs.clientHello.sessionTicket...)
    	// [Min] 对 ticket 解密，还原为 sessionState，如果无法还原，不重用
    	if hs.sessionState, ok = c.decryptTicket(sessionTicket); !ok {
    		return false
    	}

    	// Never resume a session for a different TLS version.
    	// [Min] 如果 TLS 版本不同，不重用
    	if c.vers != hs.sessionState.vers {
    		return false
    	}

    	cipherSuiteOk := false
    	// Check that the client is still offering the ciphersuite in the session.
    	// [Min] 检查客户端对该重用 session 的加密套件仍然支持
    	for _, id := range hs.clientHello.cipherSuites {
    		if id == hs.sessionState.cipherSuite {
    			cipherSuiteOk = true
    			break
    		}
    	}
    	if !cipherSuiteOk {
    		return false
    	}

    	// Check that we also support the ciphersuite from the session.
    	// [Min] 检查服务端仍然支持该套件，并设置套件
    	if !hs.setCipherSuite(hs.sessionState.cipherSuite, c.config.cipherSuites(), hs.sessionState.vers) {
    		return false
    	}

    	sessionHasClientCerts := len(hs.sessionState.certificates) != 0
    	needClientCerts := c.config.ClientAuth == RequireAnyClientCert || c.config.ClientAuth == RequireAndVerifyClientCert
    	// [Min] 如果服务端需要客户端提供证书（验证），但重用 session 中没有任何证书，则不能重用
    	if needClientCerts && !sessionHasClientCerts {
    		return false
    	}
    	// [Min] 如果 session 有证书，但服务端不要求客户端提供证书，也不能重用
    	if sessionHasClientCerts && c.config.ClientAuth == NoClientCert {
    		return false
    	}

    	return true
    }
    ```

    > 4.7 如果非重用 session，则继续协商密码套件  
    　　根据 config 配置，如果是服务器密码套件优先，则以服务器支持的密码套件为基准，去匹配客户端支持的套件，匹配成功，就设置密码套件，都不成功，则报警。反之亦然

    ```go
    	// [Min] 以下为非重用 session 的情况，我们仍需继续协商套件
    	var preferenceList, supportedList []uint16
    	// [Min] 如果优先服务器加密套件，则将服务器加密套件作为优先选择的列表，客户端发送的列表作为支持的列表
    	// [Min] 否则，相反
    	if c.config.PreferServerCipherSuites {
    		preferenceList = c.config.cipherSuites()
    		supportedList = hs.clientHello.cipherSuites
    	} else {
    		preferenceList = hs.clientHello.cipherSuites
    		supportedList = c.config.cipherSuites()
    	}

    	// [Min] 从优先选择列表中依次判断套件是否在支持列表中，且双方实现该套件的参数都可用，
    	// [Min] 是就协商成功，设置hs.suite，否就继续协商，直到preferenceList完结
    	for _, id := range preferenceList {
    		if hs.setCipherSuite(id, supportedList, c.vers) {
    			break
    		}
    	}

    	// [Min] 如果没有协商出双方都可以的套件，报警
    	if hs.suite == nil {
    		c.sendAlert(alertHandshakeFailure)
    		return false, errors.New("tls: no cipher suite supported by both client and server")
    	}

    	// See https://tools.ietf.org/html/rfc7507.
    	for _, id := range hs.clientHello.cipherSuites {
    		if id == TLS_FALLBACK_SCSV {
    			// The client is doing a fallback connection.
    			if hs.clientHello.vers < c.config.maxVersion() {
    				c.sendAlert(alertInappropriateFallback)
    				return false, errors.New("tls: client using inappropriate protocol fallback")
    			}
    			break
    		}
    	}

    	return false, nil
    ```

5. 接下来分为两种情况，一种是非重用 session 的完整握手，一种是重用 session，此时均已经开启了缓存写入的模式

    > 5.1 完整握手  
　　5.1.1 调用 hs.doFullHandshake()  
　　　　5.1.1.1 设置协商好的密码套件等信息  
　　　　5.1.1.2 与客户端类似，新建服务端 finishedHash  
　　　　5.1.1.3 完成 clientHelloMsg 和 serverHelloMsg  
　　　　5.1.1.4 将 serverHelloMsg 写入 c.sendBuf 中等待正式发送  
　　　　5.1.1.5 构造服务端证书消息 certificateMsg，完成该消息并写入 c.sendBuf 中等待正式发送  
　　　　5.1.1.6 按需构造服务端证书状态消息 certificateStatusMsg，完成该消息并写入 c.sendBuf 中等待正式发送  
　　　　5.1.1.7 根据密码套件获取 keyAgreement，调用 generateServerKeyExchange 生成服务端秘钥交换消息 serverKeyExchangeMsg（非 RSA 秘钥交换），完成该消息并写入 c.sendBuf 中等待正式发送  
　　　　5.1.1.8 根据自身需求，向客户端发送验证客户端证书的请求，构造请求消息 certificateRequestMsg，完成该消息并写入 c.sendBuf 中等待正式发送  
　　　　5.1.1.9 至此，serverHello 完成，完成 serverHelloDoneMsg 消息，并写入 c.sendBuf 中等待正式发送  
　　　　5.1.1.10 正式推送 c.sendBuf 中累积的消息给客户端，依次包括 serverHelloMsg，certificateMsg，certificateStatusMsg（可选），serverKeyExchangeMsg（非 RSA 秘钥交换），certificateRequestMsg（可选），serverHelloDoneMsg  

	```go
	// [Min] 完整的 handshake
	func (hs *serverHandshakeState) doFullHandshake() error {
		c := hs.c

		// [Min] 如果客户端要求 ocspStapling，且证书状态不为空，设置 hs.hello.ocspStapling 为真
		if hs.clientHello.ocspStapling && len(hs.cert.OCSPStaple) > 0 {
			hs.hello.ocspStapling = true
		}

		// [Min] 设置是否支持 ticket，套件 id
		hs.hello.ticketSupported = hs.clientHello.ticketSupported && !c.config.SessionTicketsDisabled
		hs.hello.cipherSuite = hs.suite.id

		// [Min] 根据版本和套件新建 finishedHash
		hs.finishedHash = newFinishedHash(hs.c.vers, hs.suite)
		// [Min] 如果不需要客户端证书，直接将 finishedHash.buffer 置为 nil
		if c.config.ClientAuth == NoClientCert {
			// No need to keep a full record of the handshake if client
			// certificates won't be used.
			hs.finishedHash.discardHandshakeBuffer()
		}
		// [Min] 计算 clientHelloMsg 和 serverHelloMsg 的 hash
		hs.finishedHash.Write(hs.clientHello.marshal())
		hs.finishedHash.Write(hs.hello.marshal())
		// [Min] 将 serverHelloMsg 写入 tls.Conn 的缓存 sendBuf 中
		if _, err := c.writeRecord(recordTypeHandshake, hs.hello.marshal()); err != nil {
			return err
		}

		// [Min] 构造certificateMsg，将服务端证书写入缓存 c.sendBuf 中，并完成该消息
		certMsg := new(certificateMsg)
		certMsg.certificates = hs.cert.Certificate
		hs.finishedHash.Write(certMsg.marshal())
		if _, err := c.writeRecord(recordTypeHandshake, certMsg.marshal()); err != nil {
			return err
		}

		// [Min] 如果需要 ocspStapling，构造 certificateStatusMsg，写入缓存 c.sendBuf 中，并完成该消息
		if hs.hello.ocspStapling {
			certStatus := new(certificateStatusMsg)
			certStatus.statusType = statusTypeOCSP
			certStatus.response = hs.cert.OCSPStaple
			hs.finishedHash.Write(certStatus.marshal())
			if _, err := c.writeRecord(recordTypeHandshake, certStatus.marshal()); err != nil {
				return err
			}
		}

		// [Min] 获得该套件的 keyAgreement 实例
		keyAgreement := hs.suite.ka(c.vers)
		// [Min] 生成交换的公钥和签名，组成 serverKeyExchangeMsg
		// [Min] 也可能不需要交换公钥，如 RSA 秘钥交换
		skx, err := keyAgreement.generateServerKeyExchange(c.config, hs.cert, hs.clientHello, hs.hello)
		if err != nil {
			c.sendAlert(alertHandshakeFailure)
			return err
		}
		// [Min] 如果 skx 不为 nil，说明不是 RSA，RSA 秘钥交换不会发送 serverKeyExchangeMsg
		// [Min] 再把 serverKeyExchangeMsg 写入缓存 c.sendBuf 中，并完成该消息
		if skx != nil {
			hs.finishedHash.Write(skx.marshal())
			if _, err := c.writeRecord(recordTypeHandshake, skx.marshal()); err != nil {
				return err
			}
		}

		// [Min] 如果服务端需要验证客户端的证书，则要发送验证请求
		if c.config.ClientAuth >= RequestClientCert {
			// Request a client certificate
			certReq := new(certificateRequestMsg)
			// [Min] 要求证书为 RSASign 或 ECDSASign
			certReq.certificateTypes = []byte{
				byte(certTypeRSASign),
				byte(certTypeECDSASign),
			}
			// [Min] >= TLS 1.2，提供服务端支持的签名算法
			if c.vers >= VersionTLS12 {
				certReq.hasSignatureAndHash = true
				certReq.supportedSignatureAlgorithms = supportedSignatureAlgorithms
			}

			// An empty list of certificateAuthorities signals to
			// the client that it may send any certificate in response
			// to our request. When we know the CAs we trust, then
			// we can send them down, so that the client can choose
			// an appropriate certificate to give to us.
			// [Min] 限定证书的授权组织
			if c.config.ClientCAs != nil {
				certReq.certificateAuthorities = c.config.ClientCAs.Subjects()
			}
			// [Min] 累计计算 hash 并写入 conn 的缓存
			hs.finishedHash.Write(certReq.marshal())
			if _, err := c.writeRecord(recordTypeHandshake, certReq.marshal()); err != nil {
				return err
			}
		}

		// [Min] 至此，hello 阶段完成，发送 helloDone 消息
		helloDone := new(serverHelloDoneMsg)
		hs.finishedHash.Write(helloDone.marshal())
		if _, err := c.writeRecord(recordTypeHandshake, helloDone.marshal()); err != nil {
			return err
		}

		// [Min] 从缓存中将累积的消息推送到客户端，依次包括：
		// [Min] serverHelloMsg，certificateMsg，certificateStatusMsg（可选），
		// [Min] serverKeyExchangeMsg（非 RSA 秘钥交换），certificateRequestMsg（可选），serverHelloDoneMsg
		if _, err := c.flush(); err != nil {
			return err
		}
	```

    > 5.2 重用 Session  
　　5.2.1 调用 hs.doResumeHandshake()  
　　　　5.2.1.1 设置协商好的密码套件，重用 sessionId 等信息，客户端需根据 sessionId 来判断是否可以重用   
　　　　5.2.1.2 与客户端类似，新建服务端 finishedHash，由于是重用，将 finishedHash 中的 buffer 置为 nil    
　　　　5.2.1.3 完成 clientHelloMsg 和 serverHelloMsg    
　　　　5.2.1.4 将 serverHelloMsg 写入 c.sendBuf 中等待正式发送  
　　　　5.2.1.5 如果重用 sessionState 中有客户端的证书信息，则对证书进行验证并更新相关字段，同时提取出客户端证书的公钥
　　　　5.2.1.6 将重用 sessionState 中的主密钥恢复到 hs.masterSecret  
　　5.2.2 调用 hs.establishKeys()  
　　　　5.2.2.1 通过主密钥生成一系列计算 hmac，加解密需要使用到的 key，和初始化向量，客户端服务端各不相同  
　　　　5.2.2.2 根据密码套件，将这些 key，iv 组合成客户端，服务端各自用于加密和计算 hmac 的 cipher，hmac  
　　　　5.2.2.3 更新到对应的 halfConn 中的预备字段中，等待正式切换  
　　5.2.3 如果 ticket 需要重制（加密 ticket 的 key 不是最新的，sessionState实际内容不变），调用 hs.sendSessionTicket() 重制 ticket 并发送给客户端让其刷新  
　　　　5.2.3.1 sessionState 内容保持不变，调用 encryptTicket，生成 ticket（encrytTicket 始终会使用最新的 sessionTicketKey 来加密）  
　　　　5.2.3.2 构造 newSessionTicketMsg，完成该消息并写入 c.sendBuf 中等待正式发送  
　　5.2.4 调用hs.sendFinished 发送finishedMsg  
　　　　5.2.4.1 发送切换信号，通知客户端此信号之后的消息都为加密消息，服务端将 c.out 切换为加密模式。注意，此信号不写入 finishedHash。  
　　　　5.2.4.2 构造 finishedMsg，finishedMsg.verifyData 是通过密码套件决定的伪随机数算法计算的伪随机数（func(result, secret, label, seed []byte)），其中secret为主密钥，label是固定的字符串，seed是到目前为止，双方所有的发送以及接收到的消息按先后顺序累积计算的 hash 值。然后完成该消息并写入 c.sendBuf 中等待正式发送，最后将 verifyData 写入c.serverFinished。  
　　　　5.2.4.3 正式推送 c.sendBuf 中累积的消息给客户端，依次包括 serverHelloMsg，newSessionTicketMsg（可选），切换信号，finishedMsg。  

    ```go
	if isResume {
		// The client has included a session ticket and so we do an abbreviated handshake.
		// [Min] 告知重用 session，验证客户端证书，恢复主密钥 hs.masterSecret = hs.sessionState.masterSecret
		if err := hs.doResumeHandshake(); err != nil {
			return err
		}
		// [Min] 根据主密钥建立加密通讯需要的 cipher，hash，更新到客户端和服务端各自对应的 halfConn 的预备字段中，等待切换
		if err := hs.establishKeys(); err != nil {
			return err
		}
		// ticketSupported is set in a resumption handshake if the
		// ticket from the client was encrypted with an old session
		// ticket key and thus a refreshed ticket should be sent.
		// [Min] 如果重用的 sessionState 是使用老的 ticketKey 解密而得，
		// [Min] 需要用最新的 key 重新加密生成新的 ticket，并返回给客户端让其同步刷新
		if hs.hello.ticketSupported {
			if err := hs.sendSessionTicket(); err != nil {
				return err
			}
		}
		// [Min] 发送finishedMsg，并将 fishishedMsg 中的 verifyData 写入 c.serverFinished[:]
		// [Min] 切换 c.out 为加密模式
		if err := hs.sendFinished(c.serverFinished[:]); err != nil {
			return err
		}
		// [Min] 推送 c.sendBuf 中累积的消息到客户端，依次包括：serverHelloMsg，newSessionTicketMsg（可选），finishedMsg。
		if _, err := c.flush(); err != nil {
			return err
		}
    ```

    ```go
    // [Min] 重用 session 的 handshake，返回 helloMsg，告知 session 重用，验证客户端证书并恢复主密钥
    func (hs *serverHandshakeState) doResumeHandshake() error {
    	c := hs.c

    	hs.hello.cipherSuite = hs.suite.id
    	// We echo the client's session ID in the ServerHello to let it know
    	// that we're doing a resumption.
    	// [Min] 重用 session 的情况下，sessionId 和客户端发过来的保持一致，
    	// [Min] 这样客户端就可以通过 sessionId 没有变化来判断 session 的重用
    	hs.hello.sessionId = hs.clientHello.sessionId
    	// [Min] 表明客户端提供的 ticket 是否可以恢复成 sessionState 使用
    	// [Min] 同时也记录 sessionTicket 是否需要以最新的 key 重制生成 ticket 来刷新（实际内容不变）
    	hs.hello.ticketSupported = hs.sessionState.usedOldKey
    	hs.finishedHash = newFinishedHash(c.vers, hs.suite)
    	hs.finishedHash.discardHandshakeBuffer()
    	hs.finishedHash.Write(hs.clientHello.marshal())
    	hs.finishedHash.Write(hs.hello.marshal())
    	// [Min] 将服务端 helloMsg 写入缓存
    	if _, err := c.writeRecord(recordTypeHandshake, hs.hello.marshal()); err != nil {
    		return err
    	}

    	// [Min] 验证客户端的证书链
    	if len(hs.sessionState.certificates) > 0 {
    		if _, err := hs.processCertsFromClient(hs.sessionState.certificates); err != nil {
    			return err
    		}
    	}

    	// [Min] 客户端证书没问题，再从 sessionState 中恢复主密钥
    	hs.masterSecret = hs.sessionState.masterSecret

    	return nil
    }
    ```

    ```go
    // [Min] 根据主密钥建立加密通讯需要的 cipher，hash，更新到客户端和服务端各自对应的 halfConn 的预备字段中，等待切换
    func (hs *serverHandshakeState) establishKeys() error {
    	c := hs.c

    	// [Min] 通过主密钥生成一系列计算 mac，加解密需要使用到的 key，和初始化向量
    	clientMAC, serverMAC, clientKey, serverKey, clientIV, serverIV :=
    		keysFromMasterSecret(c.vers, hs.suite, hs.masterSecret, hs.clientHello.random, hs.hello.random,    hs.suite.macLen, hs.suite.keyLen, hs.suite.ivLen)

    	var clientCipher, serverCipher interface{}
    	var clientHash, serverHash macFunction

    	if hs.suite.aead == nil {
    		clientCipher = hs.suite.cipher(clientKey, clientIV, true /* for reading */)
    		clientHash = hs.suite.mac(c.vers, clientMAC)
    		serverCipher = hs.suite.cipher(serverKey, serverIV, false /* not for reading */)
    		serverHash = hs.suite.mac(c.vers, serverMAC)
    	} else {
    		clientCipher = hs.suite.aead(clientKey, clientIV)
    		serverCipher = hs.suite.aead(serverKey, serverIV)
    	}

    	// [Min] 将 client 的 cipher，hash 算法更新到 in 的预备字段中，等待正式切换
    	// [Min] 将 server 的 cipher，hash 算法更新到 out 的预备字段中，等待正式切换
    	c.in.prepareCipherSpec(c.vers, clientCipher, clientHash)
    	c.out.prepareCipherSpec(c.vers, serverCipher, serverHash)

    	return nil
    }
    ```

    ```go
    // [Min] 根据当前协商好的信息，制作 sessionTicket，并返回给客户端
    func (hs *serverHandshakeState) sendSessionTicket() error {
    	if !hs.hello.ticketSupported {
    		return nil
    	}

    	c := hs.c
    	m := new(newSessionTicketMsg)

    	var err error
    	// [Min] sessionState 的内容
    	state := sessionState{
    		vers:         c.vers,
    		cipherSuite:  hs.suite.id,
    		masterSecret: hs.masterSecret,
    		certificates: hs.certsFromClient,
    	}
    	m.ticket, err = c.encryptTicket(&state)
    	if err != nil {
    		return err
    	}

    	hs.finishedHash.Write(m.marshal())
    	if _, err := c.writeRecord(recordTypeHandshake, m.marshal()); err != nil {
    		return err
    	}

    	return nil
    }
    ```

    ```go
    // [Min] 发送 finshedMsg
    func (hs *serverHandshakeState) sendFinished(out []byte) error {
    	c := hs.c

    	// [Min] 发送切换信号，此时会将 c.out 中的 cipher 和 mac 切换，转为加密模式
    	if _, err := c.writeRecord(recordTypeChangeCipherSpec, []byte{1}); err != nil {
    		return err
    	}

    	// [Min] 构造 finishedMsg，并序列化，然后完成该消息并写入 c.sendBuf 中等待正式发送
    	finished := new(finishedMsg)
    	finished.verifyData = hs.finishedHash.serverSum(hs.masterSecret)
    	hs.finishedHash.Write(finished.marshal())
    	if _, err := c.writeRecord(recordTypeHandshake, finished.marshal()); err != nil {
    		return err
    	}

    	// [Min] 同步 config 中 cipherSuite
    	c.cipherSuite = hs.suite.id
    	// [Min] 将 verifyData 拷贝至 out
    	copy(out, finished.verifyData)

    	return nil
    }
    ```

# 4. 阶段小结

　　至此，我们完成了：  
    1. 客户端从正式发送 clinetHelloMsg 到正式接收 serverHelloMsg（第一次正式发送，第一次正式接收）   
    2. 服务端从正式收到 clinetHelloMsg 到正式发送 serverHelloMsg（第一次正式接收，第一次正式发送）

正常情况下非重用 session 消息发送序列：

|批次-序号|客户端|服务端|
|:---:|:---|:---|
|1-1|clientHelloMsg|serverHelloMsg|
|1-2||certificateMsg|
|1-3||certificateStatusMsg（可选）|
|1-4||serverKeyExchangeMsg（非 RSA 秘钥交换）|
|1-5||certificateRequestMsg（可选）|
|1-6||serverHelloDoneMsg|

正常情况下重用 session 消息发送序列：

|批次-序号|客户端|服务端|
|:---:|:---|:---|
|1-1|clientHelloMsg|serverHelloMsg|
|1-2||newSessionTicketMsg（可选）|
|1-3||切换信号|
|1-4||finishedMsg|

未完待续




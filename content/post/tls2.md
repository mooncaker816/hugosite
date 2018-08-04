+++
title = "TLS（二）"
date = 2018-08-03T19:30:38+08:00
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

　　书接上回，客户端在完成 clientHelloMsg 和 serverHelloMsg 后，开启缓存写入模式，也分为重用 session 和非重用 session 两种情况。服务端在发送完第一批次消息后，等待客户端的回应。

# 1. 客户端

## 1.1 重用 session 

### 1.1.2 调用 establishKeys()，由主密钥衍生出各种实际秘钥，等待切换

1. 通过主密钥生成一系列计算 hmac，加解密需要使用到的 key，和初始化向量，客户端服务端各不相同  
2. 根据密码套件，将这些 key，iv 组合成客户端，服务端各自用于加密和计算 hmac 的 cipher，hmac  
3. 更新到对应的 halfConn 中的预备字段中，等待正式切换  

```go
// [Min] 根据主密钥建立加密通讯需要的 cipher，hash，更新到客户端和服务端各自对应的 halfConn 的预备字段中，等待切换
func (hs *clientHandshakeState) establishKeys() error {
	c := hs.c

	// [Min] 通过主密钥生成一系列计算 mac，加解密需要使用到的 key，和初始化向量
	clientMAC, serverMAC, clientKey, serverKey, clientIV, serverIV :=
		keysFromMasterSecret(c.vers, hs.suite, hs.masterSecret, hs.hello.random, hs.serverHello.random, hs.suite.macLen, hs.suite.keyLen, hs.suite.ivLen)
	var clientCipher, serverCipher interface{}
	var clientHash, serverHash macFunction
	if hs.suite.cipher != nil {
		clientCipher = hs.suite.cipher(clientKey, clientIV, false /* not for reading */)
		clientHash = hs.suite.mac(c.vers, clientMAC)
		serverCipher = hs.suite.cipher(serverKey, serverIV, true /* for reading */)
		serverHash = hs.suite.mac(c.vers, serverMAC)
	} else {
		clientCipher = hs.suite.aead(clientKey, clientIV)
		serverCipher = hs.suite.aead(serverKey, serverIV)
	}

	// [Min] 将 server 的 cipher，hash 算法更新到 in 的预备字段中，等待正式切换
	// [Min] 将 client 的 cipher，hash 算法更新到 out 的预备字段中，等待正式切换
	c.in.prepareCipherSpec(c.vers, serverCipher, serverHash)
	c.out.prepareCipherSpec(c.vers, clientCipher, clientHash)
	return nil
}
```

### 1.1.3 调用 readSessionTicket()，读取 ticket 并保存其中 session 的状态

　　注意，在重用 session 模式下，hs.serverHello.ticketSupported 只有在 ticket 需要重新加密的情况下才会设置为真，也就是说，如果该值为真，就说明服务端会发送 newSessionTicketMsg。

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
```

　　读取并完成newSessionTicketMsg，保存 ticket 以及 session 状态

```go
// [Min] 读取 newSessionTicketMsg，保存 ticket 中 session 的状态
func (hs *clientHandshakeState) readSessionTicket() error {
	// [Min] 注意此处 ticketSupported 是指服务端有没有发送 ticket 过来
	// [Min] 如果是 fullhandshake，那么只要双方都支持，服务端就会发送
	// [Min] 如果是重用 session，那么只有在 ticket 需要重制的情况下（加密 ticket 的 key 不是最新的），才会发送
	if !hs.serverHello.ticketSupported {
		return nil
	}

	c := hs.c
	// [Min] 读取 newSessionTicketMsg
	msg, err := c.readHandshake()
	if err != nil {
		return err
	}
	sessionTicketMsg, ok := msg.(*newSessionTicketMsg)
	if !ok {
		c.sendAlert(alertUnexpectedMessage)
		return unexpectedMessageError(sessionTicketMsg, msg)
	}
	hs.finishedHash.Write(sessionTicketMsg.marshal())

	// [Min] 保存 ticket 中 session 对应的状态
	hs.session = &ClientSessionState{
        sessionTicket:      sessionTicketMsg.ticket,
		vers:               c.vers,
        cipherSuite:        hs.suite.id, 
		masterSecret:       hs.masterSecret,
		serverCertificates: c.peerCertificates,
		verifiedChains:     c.verifiedChains,
	}

	return nil
}
```

### 1.1.4 调用 hs.readFinished

　　注意，如果是重用 session，是由服务端先发起 finshedMsg 的，设置clientFinishedIsFirst为假。

1. 首先读取切换信号，将客户端 c.in 切换为加密模式
2. 再读取服务端 finishedMsg
3. 通过相同的主密钥，相同的算法，以及截止目前双方理应相同的所有握手信息的 hash 值，计算本地的服务端 verify，再与服务端发送过来的 verifyData 比较，应该保持一致，否则报警
4. finishedHash 中完成此 finishedMsg
5. 将服务端 verifyData 保存到 c.serverFinished

```go
// [Min] 切换输入通道为加密模式，读取服务端 finishedMsg，并验证 verfiyData
func (hs *clientHandshakeState) readFinished(out []byte) error {
	c := hs.c

	// [Min] 首先读取切换信号，将 c.in 切换为加密模式
	c.readRecord(recordTypeChangeCipherSpec)
	if c.in.err != nil {
		return c.in.err
	}

	// [Min] 再读取 finishedMsg
	msg, err := c.readHandshake()
	if err != nil {
		return err
	}
	serverFinished, ok := msg.(*finishedMsg)
	if !ok {
		c.sendAlert(alertUnexpectedMessage)
		return unexpectedMessageError(serverFinished, msg)
	}

	// [Min] 通过相同的主密钥，相同的算法，截止目前双方理应相同的所有握手信息的 hash 值，
	// [Min] 计算本地的 verify，再与服务端发送过来的 verifyData 比较，
	// [Min] 如果不相同，报警
	verify := hs.finishedHash.serverSum(hs.masterSecret)
	if len(verify) != len(serverFinished.verifyData) ||
		subtle.ConstantTimeCompare(verify, serverFinished.verifyData) != 1 {
		c.sendAlert(alertHandshakeFailure)
		return errors.New("tls: server's Finished message was incorrect")
	}
	// [Min] 完成该 finishedMsg，并存储 verifyData 到 out 中
	hs.finishedHash.Write(serverFinished.marshal())
	copy(out, verify)
	return nil
}
```

### 1.1.5 调用客户端 sendFinished

1. 通知服务端切换其输入通道为加密模式
2. 如果是 NPN 模式，协商协议，构造并完成nextProtoMsg，然后发送至 sendBuf，等待正式推送
3. 构造客户端 finishedMsg，完成并发送至 sendBuf，等待正式推送
4. 保存客户端 verifyData

```go
// [Min] 客户端通知服务端切换加密模式，完成 NPN 协议协商，发送 finishedMsg
func (hs *clientHandshakeState) sendFinished(out []byte) error {
	c := hs.c

	// [Min] 通知服务端切换其输入通道为加密模式
	if _, err := c.writeRecord(recordTypeChangeCipherSpec, []byte{1}); err != nil {
		return err
	}
	// [Min] 如果是 NPN 模式，协商协议，构造并完成nextProtoMsg，然后发送至 sendBuf，等待正式推送
	if hs.serverHello.nextProtoNeg {
		nextProto := new(nextProtoMsg)
		proto, fallback := mutualProtocol(c.config.NextProtos, hs.serverHello.nextProtos)
		nextProto.proto = proto
		c.clientProtocol = proto
		c.clientProtocolFallback = fallback

		hs.finishedHash.Write(nextProto.marshal())
		if _, err := c.writeRecord(recordTypeHandshake, nextProto.marshal()); err != nil {
			return err
		}
	}

	// [Min] 构造客户端 finishedMsg，完成并发送至 sendBuf，等待正式推送
	finished := new(finishedMsg)
	finished.verifyData = hs.finishedHash.clientSum(hs.masterSecret)
	hs.finishedHash.Write(finished.marshal())
	if _, err := c.writeRecord(recordTypeHandshake, finished.marshal()); err != nil {
		return err
	}
	// [Min] 保存客户端 verifyData 到 c.clientFinished
	copy(out, finished.verifyData)
	return nil
}
```

### 1.1.6 推送累积的消息到服务端

　　nextProtoMsg（可选），切换信号，finishedMsg

## 1.2 非重用 session

　　完成 serverHelloMsg 的处理后，在 fullhandshake 模式下，需要对服务端依次发送的 certificateMsg，certificateStatusMsg（可选），serverKeyExchangeMsg（非 RSA 秘钥交换），certificateRequestMsg（可选），serverHelloDoneMsg 进行处理。

### 1.2.1 doFullHandshake

1. 读取服务端证书信息certificateMsg，并完成
2. 如果是首次握手，则解析证书，验证证书，保存有效证书到c.peerCertificates；如果不是首次握手，检查消息中的证书与之前存储在c.peerCertificates的证书是否相同
3. 按需读取certificateStatusMsg（可选），并完成，存储证书状态到c.ocspResponse
4. 读取serverKeyExchangeMsg（非 RSA 秘钥交换），完成消息，调用 processServerKeyExchange，从中获取服务端秘钥交换的公钥点，椭圆曲线，以及服务端用其证书私钥对椭圆曲线公钥信息的签名。客户端用服务端证书公钥对此签名进行认证。
5. 读取 certificateRequestMsg（可选），按需获取客户端证书，完成该消息。
6. 读取并完成 serverHelloDoneMsg
7. 如果需要发送客户端证书信息，构造并完成 certificateMsg ，写入 sendBuf，等待推送
8. 调用 generateClientKeyExchange，  
　　如果是 RSA 秘钥交换，生成46字节随机数，加上头两个字节的TLS版本值，就是预备主密钥，用服务端证书公钥对此预备主密钥加密，构造clientKeyExchangeMsg。  
　　如果是 ECDHE 秘钥交换，随机生成客户端秘钥交换私钥，和客户端秘钥交换公钥，构造clientKeyExchangeMsg，生成客户端秘钥交换公钥信息。再根据之前获得的服务端秘钥交换公钥，生成客户端预备主密钥。  
　　完成clientKeyExchangeMsg，写入 sendBuf，等待推送
9. 如果之前发送了客户端的证书，也要发送签名消息 certificateVerifyMsg，签名的对象是 finishedHash 中所有的握手消息（finishedHash.buffer）的 hash 值。完成该消息，写入 sendBuf，等待推送。从这里也就说明了为什么 buffer 只有在需要客户端证书的情况下才不为 nil。
10. 根据预备主密钥，客户端随机数，服务端随机数，计算主密钥
11. 清空 finishedHash 中的 buffer

　　目前缓存待推送的消息：certificateMsg（可选），clientKeyExchangeMsg，certificateVerifyMsg（可选）

```go
// [Min] 客户端 fullhandshake
func (hs *clientHandshakeState) doFullHandshake() error {
	c := hs.c

	// [Min] ServerHelloMsg之后，期待收到服务端的证书信息，证书必须存在且不为空
	msg, err := c.readHandshake()
	if err != nil {
		return err
	}
	certMsg, ok := msg.(*certificateMsg)
	if !ok || len(certMsg.certificates) == 0 {
		c.sendAlert(alertUnexpectedMessage)
		return unexpectedMessageError(certMsg, msg)
	}
	// [Min] fihishedHash 中完成certificateMsg
	hs.finishedHash.Write(certMsg.marshal())

	if c.handshakes == 0 {
		// [Min] 如果是初次握手，解析证书
		// If this is the first handshake on a connection, process and
		// (optionally) verify the server's certificates.
		certs := make([]*x509.Certificate, len(certMsg.certificates))
		for i, asn1Data := range certMsg.certificates {
			cert, err := x509.ParseCertificate(asn1Data)
			if err != nil {
				c.sendAlert(alertBadCertificate)
				return errors.New("tls: failed to parse certificate from server: " + err.Error())
			}
			certs[i] = cert
		}

		// [Min] 如果不是跳过验证，对证书进行验证，并更新 c.verifiedChains，c.peerCertificates
		if !c.config.InsecureSkipVerify {
			opts := x509.VerifyOptions{
				Roots:         c.config.RootCAs,
				CurrentTime:   c.config.time(),
				DNSName:       c.config.ServerName,
				Intermediates: x509.NewCertPool(),
			}

			for i, cert := range certs {
				if i == 0 {
					continue
				}
				opts.Intermediates.AddCert(cert)
			}
			c.verifiedChains, err = certs[0].Verify(opts)
			if err != nil {
				c.sendAlert(alertBadCertificate)
				return err
			}
		}

		// [Min] 自定义的验证
		if c.config.VerifyPeerCertificate != nil {
			if err := c.config.VerifyPeerCertificate(certMsg.certificates, c.verifiedChains); err != nil {
				c.sendAlert(alertBadCertificate)
				return err
			}
		}

		// [Min] 只支持 RSA，ECDSA 的公钥
		switch certs[0].PublicKey.(type) {
		case *rsa.PublicKey, *ecdsa.PublicKey:
			break
		default:
			c.sendAlert(alertUnsupportedCertificate)
			return fmt.Errorf("tls: server's certificate contains an unsupported type of public key: %T", certs[0].PublicKey)
		}

		// [Min] 保存解析后的证书
		c.peerCertificates = certs
	} else {
		// [Min] 不是首次握手，需确保之前存储的服务端的证书没有改变
		// This is a renegotiation handshake. We require that the
		// server's identity (i.e. leaf certificate) is unchanged and
		// thus any previous trust decision is still valid.
		//
		// See https://mitls.org/pages/attacks/3SHAKE for the
		// motivation behind this requirement.
		if !bytes.Equal(c.peerCertificates[0].Raw, certMsg.certificates[0]) {
			c.sendAlert(alertBadCertificate)
			return errors.New("tls: server's identity changed during renegotiation")
		}
	}

	// [Min] 再次读取 handshake 的 msg，此时有可能是客户端主动要求服务端发送的 certificateStatusMsg
	msg, err = c.readHandshake()
	if err != nil {
		return err
	}

	cs, ok := msg.(*certificateStatusMsg)
	if ok {
		// RFC4366 on Certificate Status Request:
		// The server MAY return a "certificate_status" message.

		// [Min] 如果服务端ocspStapling标记为假，但收到了certificateStatusMsg，报警
		if !hs.serverHello.ocspStapling {
			// If a server returns a "CertificateStatus" message, then the
			// server MUST have included an extension of type "status_request"
			// with empty "extension_data" in the extended server hello.

			c.sendAlert(alertUnexpectedMessage)
			return errors.New("tls: received unexpected CertificateStatus message")
		}
		// [Min] 累计计算 hash，并置 c.ocspResponse = cs.response
		hs.finishedHash.Write(cs.marshal())

		if cs.statusType == statusTypeOCSP {
			c.ocspResponse = cs.response
		}

		// [Min] 读取下一条 handshake 消息
		msg, err = c.readHandshake()
		if err != nil {
			return err
		}
	}

	// [Min] 根据套件获取对应的 keyAgreement
	keyAgreement := hs.suite.ka(c.vers)

	// [Min] 可能是 serverKeyExchangeMsg，如果采用的是 RSA 交换秘钥的模式，没有 serverKeyExchangeMsg
	skx, ok := msg.(*serverKeyExchangeMsg)
	if ok {
		// [Min] 如果是 serverKeyExchangeMsg，完成该消息并处理
		hs.finishedHash.Write(skx.marshal())
		// [Min] 从 serverKeyExchangeMsg 获取服务端公钥，并验证签名
		err = keyAgreement.processServerKeyExchange(c.config, hs.hello, hs.serverHello, c.peerCertificates[0], skx)
		if err != nil {
			c.sendAlert(alertUnexpectedMessage)
			return err
		}

		// [Min] 读取下一条消息
		msg, err = c.readHandshake()
		if err != nil {
			return err
		}
	}

	var chainToSend *Certificate
	var certRequested bool
	certReq, ok := msg.(*certificateRequestMsg)
	// [Min] 此时可能是服务端要求客户端发送证书的请求消息
	if ok {
		certRequested = true
		// [Min] 完成该消息
		hs.finishedHash.Write(certReq.marshal())

		// [Min] 根据要求获取客户端的证书
		if chainToSend, err = hs.getCertificate(certReq); err != nil {
			c.sendAlert(alertInternalError)
			return err
		}

		// [Min] 读取下一条消息
		msg, err = c.readHandshake()
		if err != nil {
			return err
		}
	}

	// [Min] 应该是 HelloDone 消息
	shd, ok := msg.(*serverHelloDoneMsg)
	if !ok {
		c.sendAlert(alertUnexpectedMessage)
		return unexpectedMessageError(shd, msg)
	}
	// [Min] 完成消息
	hs.finishedHash.Write(shd.marshal())

	// If the server requested a certificate then we have to send a
	// Certificate message, even if it's empty because we don't have a
	// certificate to send.
	// [Min] 发送客户端证书信息
	if certRequested {
		certMsg = new(certificateMsg)
		certMsg.certificates = chainToSend.Certificate
		hs.finishedHash.Write(certMsg.marshal())
		if _, err := c.writeRecord(recordTypeHandshake, certMsg.marshal()); err != nil {
			return err
		}
	}

	// [Min] 构造客户端秘钥交换消息，由于已经收到服务端的公钥信息，所以同时可以生成预备主密钥了
	preMasterSecret, ckx, err := keyAgreement.generateClientKeyExchange(c.config, hs.hello, c.peerCertificates[0])
	if err != nil {
		c.sendAlert(alertInternalError)
		return err
	}
	// [Min] 完成消息，并将 clientKeyExchangeMsg 写入 sendBuf，等待推送
	if ckx != nil {
		hs.finishedHash.Write(ckx.marshal())
		if _, err := c.writeRecord(recordTypeHandshake, ckx.marshal()); err != nil {
			return err
		}
	}

	// [Min] 如果发送了证书给服务端，那么也要发送签名让服务端验证
	if chainToSend != nil && len(chainToSend.Certificate) > 0 {
		certVerify := &certificateVerifyMsg{
			hasSignatureAndHash: c.vers >= VersionTLS12,
		}

		// [Min] 证书支持签名
		key, ok := chainToSend.PrivateKey.(crypto.Signer)
		if !ok {
			c.sendAlert(alertInternalError)
			return fmt.Errorf("tls: client certificate private key of type %T does not implement crypto.Signer", chainToSend.PrivateKey)
		}

		// [Min] 证书的签名类型，RSA 或 ECDSA
		var signatureType uint8
		switch key.Public().(type) {
		case *ecdsa.PublicKey:
			signatureType = signatureECDSA
		case *rsa.PublicKey:
			signatureType = signatureRSA
		default:
			c.sendAlert(alertInternalError)
			return fmt.Errorf("tls: failed to sign handshake with client certificate: unknown client certificate key type: %T", key)
		}

		// SignatureAndHashAlgorithm was introduced in TLS 1.2.
		if certVerify.hasSignatureAndHash {
			// [Min] 以证书的签名类型为基准，获取一种符合服务端要求的签名算法
			certVerify.signatureAlgorithm, err = hs.finishedHash.selectClientCertSignatureAlgorithm(certReq.supportedSignatureAlgorithms, signatureType)
			if err != nil {
				c.sendAlert(alertInternalError)
				return err
			}
		}
		// [Min] 计算finishedHash.buffer 的 hash值，作为待签名对象
		digest, hashFunc, err := hs.finishedHash.hashForClientCertificate(signatureType, certVerify.signatureAlgorithm, hs.masterSecret)
		if err != nil {
			c.sendAlert(alertInternalError)
			return err
		}
		// [Min] 对上述 hash 值以私钥采用同样的 hash 函数进行签名
		certVerify.signature, err = key.Sign(c.config.rand(), digest, hashFunc)
		if err != nil {
			c.sendAlert(alertInternalError)
			return err
		}

		// [Min] 累计计算 hash，将 certificateVerifyMsg 写入 conn 缓存
		hs.finishedHash.Write(certVerify.marshal())
		if _, err := c.writeRecord(recordTypeHandshake, certVerify.marshal()); err != nil {
			return err
		}
	}

	// [Min] 根据预备主密钥，客户端随机数，服务端随机数，计算主密钥
	hs.masterSecret = masterFromPreMasterSecret(c.vers, hs.suite, preMasterSecret, hs.hello.random, hs.serverHello.random)
	// [Min] 一般测试用
	if err := c.config.writeKeyLog(hs.hello.random, hs.masterSecret); err != nil {
		c.sendAlert(alertInternalError)
		return errors.New("tls: failed to write to key log: " + err.Error())
	}

	// [Min] 清空 finishedHash 中的 buffer
	hs.finishedHash.discardHandshakeBuffer()

	return nil
}
```

### 1.2.2 调用 establishKeys()，通过主密钥建立各种秘钥，等待切换

　　和重用 session 类似

### 1.2.3 客户端发送 nextProtoMsg（可选），finishedMsg

　　非重用 session，客户端先于服务端发送 finishedMsg，发送内容与重用 session 一致

### 1.2.4 推送消息

　　certificateMsg（可选），clientKeyExchangeMsg，certificateVerifyMsg（可选），nextProtoMsg（可选），finishedMsg

### 1.2.5 readSessionTicket()

　　读取并完成newSessionTicketMsg，保持 ticket 以及 session 状态，与重用 session 类似

### 1.2.6 readFinished

　　与重用 session 类似，只不过服务端，客户端的 finishedMsg 先后顺序不同

## 1.3 客户端 handshake 完成

1. 标注是否为重用 session，c.didResume = isResume
2. 设置	c.handshakeComplete = true
3. 将 session 缓存到 LRU 缓存结构中（sessionCache）

```go
	// [Min] 完成客户端 handshake
	c.didResume = isResume
	c.handshakeComplete = true
```

```go
	// [Min] 调用 clientHandshakeState.handshake，真正开始 handshake
	if err = hs.handshake(); err != nil {
		return err
	}

	// If we had a successful handshake and hs.session is different from
	// the one already cached - cache a new one
	// [Min] 如果 handshake 成功后，返回的 hs.session 与之前的不同，将新的 hs.session 存入缓存中，cacheKey 不变
	if sessionCache != nil && hs.session != nil && session != hs.session {
		sessionCache.Put(cacheKey, hs.session)
	}
```

# 2. 服务端

## 2.1 重用 session

　　如果是重用 session，服务端已经在第一批次的最后一条消息发送了 finishedMsg，现在只需要等待客户发送的切换信号和客户端的 finishedMsg，调用 hs.readFinished 即可。

1. 读取切换信号，切换 in 为加密模式
2. 如果是 NPN 模式，此时客户端应该已经发送了nextProtoMsg，读取并完成该消息，更新协议
3. 读取 finishedMsg，并验证客户端发来的 verifyData，完成 finishedMsg 并保存 verifyData

```go
// [Min] 读取客户端 finishedMsg
func (hs *serverHandshakeState) readFinished(out []byte) error {
	c := hs.c

	// [Min] 首先客户端也应该先返回一个 recordTypeChangeCipherSpec 的消息
	// [Min] 此时会将 c.in 的 cipher，mac 切换为之前协商后的结果
	c.readRecord(recordTypeChangeCipherSpec)
	if c.in.err != nil {
		return c.in.err
	}

	// [Min] 如果是 NPN 模式，此时应该收到客户端的对此的回复
	if hs.hello.nextProtoNeg {
		msg, err := c.readHandshake()
		if err != nil {
			return err
		}
		nextProto, ok := msg.(*nextProtoMsg)
		if !ok {
			c.sendAlert(alertUnexpectedMessage)
			return unexpectedMessageError(nextProto, msg)
		}
		hs.finishedHash.Write(nextProto.marshal())
		c.clientProtocol = nextProto.proto
	}

	// [Min] 接下来应该收到客户端的 finishedMsg
	msg, err := c.readHandshake()
	if err != nil {
		return err
	}
	clientFinished, ok := msg.(*finishedMsg)
	if !ok {
		c.sendAlert(alertUnexpectedMessage)
		return unexpectedMessageError(clientFinished, msg)
	}

	// [Min] 计算 clientSum，并验证 clientFinished.verifyData 是否一致
	verify := hs.finishedHash.clientSum(hs.masterSecret)
	if len(verify) != len(clientFinished.verifyData) ||
		subtle.ConstantTimeCompare(verify, clientFinished.verifyData) != 1 {
		c.sendAlert(alertHandshakeFailure)
		return errors.New("tls: client's Finished message is incorrect")
	}

	// [Min] 再次计算客户端发送的 finishedMsg 的 hash 并将 verify 拷贝至 out
	hs.finishedHash.Write(clientFinished.marshal())
	copy(out, verify)
	return nil
}
```

## 2.2 非重用 session

　　非重用 session，服务端此时已经完成了 serverHelloDoneMsg。

### 2.2.1 如果之前向客户端提出了证书的请求，此时应该收到 certificateMsg

1. 完成certificateMsg
2. 提取客户端证书公钥
3. 读取下一条消息

```go
	// [Min] 读取 handshake 返回消息
	msg, err := c.readHandshake()
	if err != nil {
		return err
	}

	var ok bool
	// If we requested a client certificate, then the client must send a
	// certificate message, even if it's empty.
	if c.config.ClientAuth >= RequestClientCert {
		// [Min] 如果之前要求了客户端提供证书，此时应该先收到证书消息
		if certMsg, ok = msg.(*certificateMsg); !ok {
			c.sendAlert(alertUnexpectedMessage)
			return unexpectedMessageError(certMsg, msg)
		}
		// [Min] 累计计算 hash
		hs.finishedHash.Write(certMsg.marshal())

		// [Min] 如果证书消息中并没有实际包含证书，但服务端又要求有证书，报警
		if len(certMsg.certificates) == 0 {
			// The client didn't actually send a certificate
			switch c.config.ClientAuth {
			case RequireAnyClientCert, RequireAndVerifyClientCert:
				c.sendAlert(alertBadCertificate)
				return errors.New("tls: client didn't provide a certificate")
			}
		}

		// [Min] 处理客户端的证书，返回公钥
		pub, err = hs.processCertsFromClient(certMsg.certificates)
		if err != nil {
			return err
		}

		// [Min] 读取下一条消息
		msg, err = c.readHandshake()
		if err != nil {
			return err
		}
	}
```

### 2.2.2 客户端秘钥交换消息 clientKeyExchangeMsg

1. 完成 clientKeyExchangeMsg
2. 调用processClientKeyExchange，根据客户端发来的交换秘钥的公钥计算预备主密钥    
　　如果是 RSA 秘钥交换算法，直接用服务端证书的私钥解密，即可得到明文预备主密钥  
　　如果是 ECDHE 秘钥交换算法，用之前生成的秘钥交换算法私钥和客户端传来的公钥点相乘，即可得到共享秘钥点，该点的 x 坐标值即为预备主密钥  
3. 再由预备主密钥，客户端随机数，服务端随机数计算主密钥

```go
	// Get client key exchange
	// [Min] 接下来应该收到客户端交换 key 的消息
	ckx, ok := msg.(*clientKeyExchangeMsg)
	if !ok {
		c.sendAlert(alertUnexpectedMessage)
		return unexpectedMessageError(ckx, msg)
	}
	// [Min] 完成消息
	hs.finishedHash.Write(ckx.marshal())

	// [Min] 此时有了客户端交换秘钥的公钥，就可以生成预备主密钥了
	preMasterSecret, err := keyAgreement.processClientKeyExchange(c.config, hs.cert, ckx, c.vers)
	if err != nil {
		c.sendAlert(alertHandshakeFailure)
		return err
	}
	// [Min] 计算主密钥
	hs.masterSecret = masterFromPreMasterSecret(c.vers, hs.suite, preMasterSecret, hs.clientHello.random, hs.hello.random)
	if err := c.config.writeKeyLog(hs.clientHello.random, hs.masterSecret); err != nil {
		c.sendAlert(alertInternalError)
		return err
	}
```

### 2.2.3 如果之前客户端发来了证书，验证签名 certificateVerifyMsg

1. 获取 certificateVerifyMsg
2. 明确 certificateVerifyMsg 中的签名算法
3. 检查客户端证书公钥与签名算法是否匹配
4. 用客户端证书公钥验证签名
5. 完成 certificateVerifyMsg
6. 清空 finishedHash 中的 buffer

```go
	// If we received a client cert in response to our certificate request message,
	// the client will send us a certificateVerifyMsg immediately after the
	// clientKeyExchangeMsg. This message is a digest of all preceding
	// handshake-layer messages that is signed using the private key corresponding
	// to the client's certificate. This allows us to verify that the client is in
	// possession of the private key of the certificate.
	// [Min] 验证客户端的签名
	if len(c.peerCertificates) > 0 {
		// [Min] 读取一条消息，理应是 certificateVerifyMsg
		msg, err = c.readHandshake()
		if err != nil {
			return err
		}
		certVerify, ok := msg.(*certificateVerifyMsg)
		if !ok {
			c.sendAlert(alertUnexpectedMessage)
			return unexpectedMessageError(certVerify, msg)
		}

		// Determine the signature type.
		// [Min] 获取签名算法
		var signatureAlgorithm SignatureScheme
		var sigType uint8
		if certVerify.hasSignatureAndHash {
			signatureAlgorithm = certVerify.signatureAlgorithm
			if !isSupportedSignatureAlgorithm(signatureAlgorithm, supportedSignatureAlgorithms) {
				return errors.New("tls: unsupported hash function for client certificate")
			}
			sigType = signatureFromSignatureScheme(signatureAlgorithm)
		} else {
			// Before TLS 1.2 the signature algorithm was implicit
			// from the key type, and only one hash per signature
			// algorithm was possible. Leave signatureAlgorithm
			// unset.
			switch pub.(type) {
			case *ecdsa.PublicKey:
				sigType = signatureECDSA
			case *rsa.PublicKey:
				sigType = signatureRSA
			}
		}

		// [Min] 验证签名
		switch key := pub.(type) {
		case *ecdsa.PublicKey:
			if sigType != signatureECDSA {
				err = errors.New("tls: bad signature type for client's ECDSA certificate")
				break
			}
			ecdsaSig := new(ecdsaSignature)
			if _, err = asn1.Unmarshal(certVerify.signature, ecdsaSig); err != nil {
				break
			}
			if ecdsaSig.R.Sign() <= 0 || ecdsaSig.S.Sign() <= 0 {
				err = errors.New("tls: ECDSA signature contained zero or negative values")
				break
			}
			var digest []byte
			if digest, _, err = hs.finishedHash.hashForClientCertificate(sigType, signatureAlgorithm, hs.masterSecret); err != nil {
				break
			}
			if !ecdsa.Verify(key, digest, ecdsaSig.R, ecdsaSig.S) {
				err = errors.New("tls: ECDSA verification failure")
			}
		case *rsa.PublicKey:
			if sigType != signatureRSA {
				err = errors.New("tls: bad signature type for client's RSA certificate")
				break
			}
			var digest []byte
			var hashFunc crypto.Hash
			if digest, hashFunc, err = hs.finishedHash.hashForClientCertificate(sigType, signatureAlgorithm, hs.masterSecret); err != nil {
				break
			}
			err = rsa.VerifyPKCS1v15(key, hashFunc, digest, certVerify.signature)
		}
		if err != nil {
			c.sendAlert(alertBadCertificate)
			return errors.New("tls: could not validate signature of connection nonces: " + err.Error())
		}

		hs.finishedHash.Write(certVerify.marshal())
	}

	// [Min] 客户端证书验证完毕，清空 finishedHash 的 buffer
	hs.finishedHash.discardHandshakeBuffer()
```

### 2.2.4 调用 hs.establishKeys()，根据主密钥生成各种加密秘钥，等待切换

```go
// [Min] 根据主密钥建立加密通讯需要的 cipher，hash，更新到客户端和服务端各自对应的 halfConn 的预备字段中，等待切换
func (hs *serverHandshakeState) establishKeys() error {
	c := hs.c

	// [Min] 通过主密钥生成一系列计算 mac，加解密需要使用到的 key，和初始化向量
	clientMAC, serverMAC, clientKey, serverKey, clientIV, serverIV :=
		keysFromMasterSecret(c.vers, hs.suite, hs.masterSecret, hs.clientHello.random, hs.hello.random, hs.suite.macLen, hs.suite.keyLen, hs.suite.ivLen)

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

### 2.2.5 调用 hs.readFinished

　　和重用 session 类似，客户端，服务端先后顺序不同而已

### 2.2.6 调用 sendSessionTicket 

1. 根据 session 状态加密 ticket 
2. 由 ticket 构造 newSessionTicketMsg，完成并写入 sendBuf，等待推送

```go
// [Min] 将 sessionState 转为 sessionTicket
func (c *Conn) encryptTicket(state *sessionState) ([]byte, error) {
	// [Min] 首先序列化 sessionState
	serialized := state.marshal()
	// [Min] ticket 结构：ticketKeyName + iv + 加密后的序列化流 + mac
	encrypted := make([]byte, ticketKeyNameLen+aes.BlockSize+len(serialized)+sha256.Size)
	keyName := encrypted[:ticketKeyNameLen]
	iv := encrypted[ticketKeyNameLen : ticketKeyNameLen+aes.BlockSize]
	macBytes := encrypted[len(encrypted)-sha256.Size:]

	// [Min] iv 为16字节的随机数
	if _, err := io.ReadFull(c.config.rand(), iv); err != nil {
		return nil, err
	}
	// [Min] 从 config 中获取 sessionTicketKeys ，用来将 sessionState 加密为 ticket
	// [Min] 注意，加密的时候总是使用第一个 sessionTicketKey，后续的都认为是老的 key
	key := c.config.ticketKeys()[0]
	// [Min] 从 key 中获取 keyName，并以 key.aseKey 为秘钥，iv 为初始向量，CTR 模式对序列化流加密
	copy(keyName, key.keyName[:])
	block, err := aes.NewCipher(key.aesKey[:])
	if err != nil {
		return nil, errors.New("tls: failed to create cipher while encrypting ticket: " + err.Error())
	}
	cipher.NewCTR(block, iv).XORKeyStream(encrypted[ticketKeyNameLen+aes.BlockSize:], serialized)

	// [Min] 对 keyName + iv + 加密的序列化流 以 key.hmacKey 为秘钥计算 HMAC
	mac := hmac.New(sha256.New, key.hmacKey[:])
	mac.Write(encrypted[:len(encrypted)-sha256.Size])
	mac.Sum(macBytes[:0])

	return encrypted, nil
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

### 2.2.7 调用服务端 hs.sendFinished

1. 发送切换信号，并将 out 转为加密模式
2. 构造 finishedMsg，写入 verifyData，完成并写入 sendBuf，等待推送
3. 更新 config 中套件，并保存 verfiyData

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

### 2.2.8 推送消息

　　newSessionTicketMsg，切换信号，finishedMsg

## 2.3 服务端完成 handshake

# 3. 整个握手过程中的消息流

正常情况下非重用 session 消息发送序列：

|批次-序号|客户端|服务端|
|:---:|:---|:---|
|1-1|clientHelloMsg|serverHelloMsg|
|1-2||certificateMsg|
|1-3||certificateStatusMsg（可选）|
|1-4||serverKeyExchangeMsg（非 RSA 秘钥交换）|
|1-5||certificateRequestMsg（可选）|
|1-6||serverHelloDoneMsg|
|2-1|certificateMsg（可选）|newSessionTicketMsg|
|2-2|clientKeyExchangeMsg|切换信号|
|2-3|certificateVerifyMsg（可选）|finishedMsg|
|2-4|切换信号||
|2-5|nextProtoMsg（可选）||
|2-6|finishedMsg||

正常情况下重用 session 消息发送序列：

|批次-序号|客户端|服务端|
|:---:|:---|:---|
|1-1|clientHelloMsg|serverHelloMsg|
|1-2||newSessionTicketMsg（可选）|
|1-3||切换信号|
|1-4||finishedMsg|
|2-1|切换信号||
|2-2|nextProtoMsg（可选）||
|2-2|finishedMsg||

# 4. 实际处理 Timeline

非重用 session：

|序号|步骤|
|:---:|:---|
|1| 客户端准备 clientHelloMsg，包含了协商的版本，套件，重用 sessionId，客户端随机数等信息|
|2| 客户端发送 clientHelloMsg（客户端第一次推送）|
|3| 服务端读取 clientHelloMsg，获得客户端随机数|
|4| 服务端协商各种参数，生成服务端随机数|
|5| 服务端按照客户端的要求获取服务端证书|
|6| 服务端判断是否重用 session（否）|
|7| 服务端协商套件|
|8| 服务端完成 serverHelloMsg，写入 sendBuf，等待推送|
|9| 服务端完成 certificateMsg，写入 sendBuf，等待推送|
|10| 服务端完成 certificateStatusMsg（按需可选），写入 sendBuf，等待推送|
|11| 服务端完成 serverKeyExchangeMsg（非 RSA 秘钥交换），写入 sendBuf，等待推送|
|12| 服务端完成 certificateRequestMsg（按需可选），写入 sendBuf，等待推送|
|13| 服务端完成 serverHelloDoneMsg，写入 sendBuf，等待推送|
|14| 服务端第一次推送|
|15| 客户端读取 serverHelloMsg，根据协商结果，完成相关参数的设置，同时获得服务端随机数|
|16| 客户端读取 certificateMsg，完成对服务端证书的解析，基本验证|
|17| 客户端读取 certificateStatusMsg（按需可选），完成服务端证书状态的设置|
|18| 客户端读取 serverKeyExchangeMsg（非 RSA 秘钥交换），获取服务端秘钥交换公钥，并以服务端证书公钥验证签名|
|19| 客户端读取 certificateRequestMsg（按需可选），准备好客户端证书|
|20| 客户端读取 serverHelloDoneMsg，准备开始回应服务端|
|21| 客户端完成 certificateMsg（按需可选），回应服务端要求的证书信息，写入 sendBuf，等待推送|
|22| 客户端完成 clientKeyExchangeMsg，发送客户端秘钥交换信息，写入 sendBuf，等待推送，同时生成预备主密钥|
|23| 客户端完成 certificateVerifyMsg（按需可选），发送客户端证书签名，让服务端验证，写入 sendBuf，等待推送|
|24| 客户端生成主密钥，再由主密钥衍生出各种秘钥|
|25| 客户端发送切换信号，写入 sendBuf，等待推送，将输出通道转为加密模式|
|26| 客户端完成 nextProtoMsg（按需可选），写入 sendBuf，等待推送|
|27| 客户端完成 finishedMsg，写入 sendBuf，等待推送|
|28| 客户端第二次推送|
|29| 服务端读取 certificateMsg（按需可选），获得客户端证书，解析，基本验证，并提取证书公钥|
|30| 服务端读取 clientKeyExchangeMsg，获得客户端秘钥交换信息，生成预备主密钥|
|31| 服务端生成主密钥|
|32| 服务端读取 certificateVerifyMsg（按需可选），并以客户端证书公钥进行签名验证|
|33| 服务端由主密钥衍生出各种秘钥|
|34| 服务端读取切换信号，将输入通道转为加密模式|
|35| 服务端读取 nextProtoMsg（按需可选），更新协议|
|36| 服务端读取 finishedMsg，并对 finishedMsg 中的 verifyData 进行验证|
|37| 服务端根据当前使用的 session 制作 sessionTicket，完成 newSessionTicketMsg，写入 sendBuf，等待推送|
|38| 服务端发送切换信号，写入 sendBuf，等待推送，将输出通道转为加密模式|
|39| 服务端完成 finishedMsg，写入 sendBuf，等待推送|
|40| 服务端第二次推送|
|41| 服务端完成握手|
|42| 客户端读取 newSessionTicketMsg，保存 ticket 和 session 状态|
|43| 客户端读取切换信号，将输入通道转为加密模式|
|44| 客户端读取 finishedMsg，并对 finishedMsg 中的 verifyData 进行验证|
|45| 客户端缓存 session 到本地 sessionCache|
|46| 客户端完成握手|

重用 session：

|序号|步骤|
|:---:|:---|
|1| 客户端准备 clientHelloMsg，包含了协商的版本，套件，重用 sessionId，客户端随机数等信息|
|2| 客户端发送 clientHelloMsg（客户端第一次推送）|
|3| 服务端读取 clientHelloMsg，获得客户端随机数|
|4| 服务端协商各种参数，生成服务端随机数|
|5| 服务端按照客户端的要求获取服务端证书|
|6| 服务端判断是否重用 session（是）|
|7| 服务端完成 serverHelloMsg，写入 sendBuf，等待推送|
|8| 服务端对重用 session 中包含的客户端证书进行解析，基本验证，并提取证书公钥（如果重用 session 中有的话）|
|9| 服务端从重用 session 中恢复主密钥，并根据主密钥衍生出各种秘钥|
|10| 服务端重制 sessionTicket（如果加密 ticket 的 key 不是最新的 ticketKey），完成 newSessionTicketMsg，写入 sendBuf，等待推送|
|11| 服务端发送切换信号，将输出通道转为加密模式|
|12| 服务端完成 finishedMsg，写入 sendBuf，等待推送|
|13| 服务端第一次推送|
|14| 客户端读取 serverHelloMsg，根据协商结果，完成相关参数的设置，同时获得服务端随机数|
|15| 客户端根据 sessionId 得知可以重用 session|
|16| 客户端从重用 session 中恢复主密钥，并由主密钥衍生出各种秘钥|
|17| 客户端根据 severHelloMsg.ticketSupported 得知 ticket 是否被服务端重制，按需读取 newSessionTicketMsg，更新 session 对应的 ticket|
|18| 客户端读取切换信号，将输入通道转为加密模式|
|19| 客户端读取 finishedMsg，并对 finishedMsg 中的 verifyData 进行验证|
|20| 客户端发送切换信号，将输出通道转为加密模式|
|21| 客户端完成 nextProtoMsg（按需可选），通知服务端选择的协议，写入 sendBuf，等待推送|
|22| 客户端完成 finishedMsg，写入 sendBuf，等待推送|
|23| 客户端第二次推送|
|24| 客户端将重制了的 ticket 的 session 缓存到本地 sessionCache|
|25| 客户端完成握手|
|26| 服务端读取切换信号，将输入通道转为加密模式|
|27| 服务端读取 nextProtoMsg（按需可选），设置协议|
|28| 服务端读取 finishedMsg，并对 finishedMsg 中的 verifyData 进行验证|
|29| 服务端完成握手|

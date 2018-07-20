+++
title = "单向散列函数"
date = 2018-07-19T19:29:32+08:00
draft = false

# Tags and categories
# For example, use `tags = []` for no tags, or the form `tags = ["A Tag", "Another Tag"]` for one or more tags.
tags = ["单向散列函数"]
categories = ["Golang","密码学"]

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

# 1 概念

　　单向散列函数，又称单向Hash函数、杂凑函数，就是把任意长的输入消息串变化成固定长的输出串且由输出串难以得到输入串的一种函数。这个输出串称为该消息的散列值。一般用于产生消息摘要，密钥加密，常见的如 MD5，SHAx，HMAC 等。  
　　具体来说，单向散列函数有一个输入，一个输出，其中输入称为消息，输出称为散列值。这里的消息可以是任何类型的数据，对于散列函数来说，它们只不过是一大串比特流。  
　　散列值的长度与消息的长度无关，其值由选择的散列函数决定。下表是常见散列函数对应的散列值长度。

散列类型 | 最大消息长度 | 散列值长度 | 分块大小 | 块内分组 | 单值字节序
:-------:|:------------:|:----------:|:--------:|:--------:|:----------:
MD5|无限制|16 bytes(128 bits)|64 bytes(512 bits)|16 * uint32|littleEndian
SHA1|2^64-1|20 bytes(160 bits)|64 bytes(512 bits)|16 * uint32|bigEndian
SHA-224|2^64-1|28 bytes(224 bits)|64 bytes(512 bits)|(16 + 48) * uint32|bigEndian
SHA-256|2^64-1|32 bytes(256 bits)|64 bytes(512 bits)|(16 + 48) * uint32|bigEndian
SHA-384|2^128-1|48 bytes(384 bits)|128 bytes(1024 bits)|(16 + 64) * uint64|bigEndian
SHA-512|2^128-1|64 bytes(512 bits)|128 bytes(1024 bits)|(16 + 64) * uint64|bigEndian
SHA-512/224|2^128-1|28 bytes(224 bits)|128 bytes(1024 bits)|(16 + 64) * uint64|bigEndian
SHA-512/256|2^128-1|32 bytes(256 bits)|128 bytes(1024 bits)|(16 + 64) * uint64|bigEndian
SHA3-224|无限制|28 bytes(224 bits)|144 bytes(1152 bits)|
SHA3-256|无限制|32 bytes(256 bits)|136 bytes(1088 bits)|
SHA3-384|无限制|48 bytes(384 bits)|104 bytes(832 bits)|
SHA3-512|无限制|64 bytes(512 bits)|72 bytes(576 bits)|
SHAKE128|无限制|变长|168 bytes(1344 bits)|
SHAKE256|无限制|变长|136 bytes(1088 bits)|

注：对于 MD5 来说，如果根据最后一个分块末尾用来记录源数据字节长度的空间大小（8个字节）来看，其最大输入长度应该为2^64 - 1，但是在 MD5 的算法中，指明了此处的值是对 2^64 取余,所以 MD5 的输入没有限制。（但是 Go 中并没有取余）

> The remaining bits are filled up with 64 bits representing the length of the original message, modulo 264.

# 2 MD5 

## 2.1 预备函数

\begin{align}
F(B,C,D) &= (B \land C) | (\lnot B \land D) \\\\\[2ex] 
G(B,C,D) &= (B \land D) | (C \land \lnot D) \\\\\[2ex]
H(B,C,D) &= B \oplus C \oplus D \\\\\[2ex]
I(B,C,D) &= C \oplus (B \lor \lnot D) 
\end{align}

F,G 更高效的表达：
\begin{align}
F(B,C,D) &= D \oplus (B \land (C \oplus D)) \\\\\[2ex] 
G(B,C,D) &= C \oplus (D \land (B \oplus C))
\end{align}  

\begin{align}
FF(a,b,c,d,Mj,s,ti) 表示&a=b+((a+F(b,c,d)+Mj+ti)\lll s) \\\\\[2ex]
GG(a,b,c,d,Mj,s,ti) 表示&a=b+((a+G(b,c,d)+Mj+ti)\lll s) \\\\\[2ex]
HH(a,b,c,d,Mj,s,ti) 表示&a=b+((a+H(b,c,d)+Mj+ti)\lll s) \\\\\[2ex]
II(a,b,c,d,Mj,s,ti) 表示&a=b+((a+I(b,c,d)+Mj+ti)\lll s)
\end{align}

## 2.2 具体实现

　　假设我们有一串消息 data，长度位 n 个字节，以下是获取其 MD5 信息摘要的步骤：

- 以64字节为单位，对 n 个字节进行分块，$$n = k*64 + r, k = 0,1,2...,r \in [0,64) $$
- 对这 k 个分块中的数据依次调用 MD5 HASH 函数，计算出这 k 个分块对应的散列值
- 对剩下的 r 个字节进行填充，  
    如果 r >= 56，先填充至64个字节，第一位填充1，后续填充0，即填满一个分块  
    如果 r < 56，先填充至56个字节，第一位填充1，后续填充0，再将原始数据对应的字节长度信息以 uint64 为类型，按小字节序填入该分块的最末尾8个字节
- 处理填充分块，可能只有一个填充分块，也可能有两个
- 块内按小字节序将64字节数据分为16组uint32，对这16组数据进行共计4轮64次循环计算
- 整合最终散列值

## 2.3 Go 源码分析

```go
// Copyright 2009 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

//go:generate go run gen.go -full -output md5block.go

// Package md5 implements the MD5 hash algorithm as defined in RFC 1321.
//
// MD5 is cryptographically broken and should not be used for secure
// applications.
package md5

import (
	"crypto"
	"errors"
	"hash"
)

func init() {
	crypto.RegisterHash(crypto.MD5, New)
}

// The size of an MD5 checksum in bytes.
// [Min] MD5 消息摘要的字节数，16 字节，128 bits
const Size = 16

// The blocksize of MD5 in bytes.
// [Min] 分块的大小 64 字节
const BlockSize = 64

const (
	chunk = 64         // [Min] 一个分块的字节长度，64 字节，512 位
	init0 = 0x67452301 // [Min] 初始摘要中0-3字节的值
	init1 = 0xEFCDAB89 // [Min] 初始摘要中4-7字节的值
	init2 = 0x98BADCFE // [Min] 初始摘要中8-11字节的值
	init3 = 0x10325476 // [Min] 初始摘要中12-15字节的值
)

/* [Min]
1. 先将源数据以64字节为单位分块，留出不够一个分块的部分 B ，其余部分 A 为64字节的整数倍
2. 将 A 中的数据依次按分块处理
3. 对 B 进行以下填充，使得 B % 64 = 56， 单位为字节
如果 B 不满 56 字节（448位），第一位填充1，后续填充 0 至448位即可，等待最终长度的填充
如果 B >= 56 字节，则需填充 (64 - B)*8 + 448 位，第一位为1，后续为0，
并且此时会形成一个满的分块，对此分块处理，剩余 448 位等待最终长度填充后达到512位后一起处理
4. 最后将源数据和所有填充数据的长度以 uint64 的类型填充到上述 448 位后，形成最后一个分块
对此分块进行处理
*/
// digest represents the partial evaluation of a checksum.
// [Min] 消息摘要
type digest struct {
	s   [4]uint32   // [Min] 存储摘要的实际载体
	x   [chunk]byte // [Min] 填充分块
	nx  int         // [Min] 当前填充分块中未处理数据的字节长度
	len uint64      // [Min] 源消息的长度
}

// [Min] 重置摘要，将载体中的值按初始值初始化
func (d *digest) Reset() {
	d.s[0] = init0
	d.s[1] = init1
	d.s[2] = init2
	d.s[3] = init3
	d.nx = 0
	d.len = 0
}

const (
	magic = "md5\x01"
	// [Min] MarshalBinary 返回的字节长度 ：
	// [Min] magic 头长度 + 16 字节消息摘要长度 + 64 字节最后一个分块长度 + 8 字节源消息大小的长度
	marshaledSize = len(magic) + 4*4 + chunk + 8
)

// [Min] 调用 Write 方法后，将当前 d 中数据格式化，用于反应 hash 过程中的状态
func (d *digest) MarshalBinary() ([]byte, error) {
	b := make([]byte, 0, marshaledSize)
	// [Min] 头
	b = append(b, magic...)
	// [Min] 当前已处理分块的消息摘要
	b = appendUint32(b, d.s[0])
	b = appendUint32(b, d.s[1])
	b = appendUint32(b, d.s[2])
	b = appendUint32(b, d.s[3])
	// [Min] 将填充分块中的还在等待填充的数据写入 b
	b = append(b, d.x[:d.nx]...)
	// [Min] 撑满一个分块的大小
	b = b[:len(b)+len(d.x)-int(d.nx)] // already zero
	// [Min] 当前已处理的数据的长度（可能包括填充数据）写入 b
	b = appendUint64(b, d.len)
	return b, nil
}

// [Min] 根据 digest 的状态（marshal 后的字节流），还原 digest
func (d *digest) UnmarshalBinary(b []byte) error {
	// [Min] 必须有 magic 头
	if len(b) < len(magic) || string(b[:len(magic)]) != magic {
		return errors.New("crypto/md5: invalid hash state identifier")
	}
	// [Min] b 的长度是固定的 marshaledSize
	if len(b) != marshaledSize {
		return errors.New("crypto/md5: invalid hash state size")
	}
	b = b[len(magic):]
	// [Min] 还原当前的消息摘要
	b, d.s[0] = consumeUint32(b)
	b, d.s[1] = consumeUint32(b)
	b, d.s[2] = consumeUint32(b)
	b, d.s[3] = consumeUint32(b)
	// [Min] 还原填充分块数据
	b = b[copy(d.x[:], b):]
	// [Min] 还原已处理数据（可能包括填充数据）长度
	b, d.len = consumeUint64(b)
	// [Min] 还原填充分块中待填充的数据的长度
	d.nx = int(d.len) % chunk
	return nil
}

// [Min] 将 x 对应的8个字节由高到低依次存入 b 中
func appendUint64(b []byte, x uint64) []byte {
	a := [8]byte{
		byte(x >> 56),
		byte(x >> 48),
		byte(x >> 40),
		byte(x >> 32),
		byte(x >> 24),
		byte(x >> 16),
		byte(x >> 8),
		byte(x),
	}
	return append(b, a[:]...)
}

// [Min] 将 x 对应的4个字节由高到低依次存入 b 中
func appendUint32(b []byte, x uint32) []byte {
	a := [4]byte{
		byte(x >> 24),
		byte(x >> 16),
		byte(x >> 8),
		byte(x),
	}
	return append(b, a[:]...)
}

// [Min] 将 b 中前8个字节当成一个 uint64 数值，返回剩余部分和该数值
func consumeUint64(b []byte) ([]byte, uint64) {
	_ = b[7]
	x := uint64(b[7]) | uint64(b[6])<<8 | uint64(b[5])<<16 | uint64(b[4])<<24 |
		uint64(b[3])<<32 | uint64(b[2])<<40 | uint64(b[1])<<48 | uint64(b[0])<<56
	return b[8:], x
}

// [Min] 将 b 中前4个字节当成一个 uint32 数值，返回剩余部分和该数值
func consumeUint32(b []byte) ([]byte, uint32) {
	_ = b[3]
	x := uint32(b[3]) | uint32(b[2])<<8 | uint32(b[1])<<16 | uint32(b[0])<<24
	return b[4:], x
}

// New returns a new hash.Hash computing the MD5 checksum. The Hash also
// implements encoding.BinaryMarshaler and encoding.BinaryUnmarshaler to
// marshal and unmarshal the internal state of the hash.
// [Min] 构造一个 MD5 类型的 hash 载体
func New() hash.Hash {
	d := new(digest)
	d.Reset()
	return d
}

// [Min] 返回 MD5 摘要的字节长度16
func (d *digest) Size() int { return Size }

// [Min] 返回 MD5 的 BlockSize 64
func (d *digest) BlockSize() int { return BlockSize }

func (d *digest) Write(p []byte) (nn int, err error) {
	nn = len(p)
	d.len += uint64(nn)
	// [Min] 如果 d.nx >0, 说明 d.x 中含有遗留的未处理的尾部源数据（不够一个分块的部分）
	// [Min] 此时 p 中的数据为填充数据，
	// [Min] 如果填满了一个分块，就进行处理
	// [Min] 如果没满，说明还在等待最后的长度填充（届时一定能恰好填满一个分块）
	if d.nx > 0 {
		n := copy(d.x[d.nx:], p)
		d.nx += n
		if d.nx == chunk {
			block(d, d.x[:])
			d.nx = 0
		}
		p = p[n:]
	}
	// [Min] 源数据超过一个分块的大小，此处的 p 为源数据
	if len(p) >= chunk {
		// [Min] 计算出 p 中最大整数倍分块大小的字节长度 n，
		// [Min] 对这 n 个字节先处理，剩余部分比分块大小小，存入 p 中
		n := len(p) &^ (chunk - 1)
		block(d, p[:n])
		p = p[n:]
	}
	// [Min] p 中数据不够一个分块，存入 d.x 中，待后续调用 Write 时再处理
	if len(p) > 0 {
		d.nx = copy(d.x[:], p)
	}
	return
}

func (d0 *digest) Sum(in []byte) []byte {
	// Make a copy of d0 so that caller can keep writing and summing.
	d := *d0
	hash := d.checkSum()
	return append(in, hash[:]...)
}

func (d *digest) checkSum() [Size]byte {
	// Padding. Add a 1 bit and 0 bits until 56 bytes mod 64.
	// [Min] 获得填充前的源消息字节长度
	len := d.len
	var tmp [64]byte
	// [Min] 填充信息，最高位为1，后续全为0
	tmp[0] = 0x80
	// [Min] 如果不满56字节（448位），填充至56字节即可
	// [Min] 如果超过或等于56字节，需填满一个分块64字节，再填56字节
	if len%64 < 56 {
		d.Write(tmp[0 : 56-len%64])
	} else {
		d.Write(tmp[0 : 64+56-len%64])
	}

	// Length in bits.
	// [Min] 将字节长度转为 bit 位长，再将其存入8个字节中，代表一个 uint64 值
	// [Min] 再将这8个字节填入剩余部分，构成最后一个分块（小字节序）
	len <<= 3
	for i := uint(0); i < 8; i++ {
		tmp[i] = byte(len >> (8 * i))
	}
	d.Write(tmp[0:8])

	// [Min] 此时 d.nx 必须为0， 代表 d.x 中的分块已处理
	if d.nx != 0 {
		panic("d.nx != 0")
	}

	// [Min] 所有分块都处理完后，将最终128位摘要信息按小字节序写入对应的16个字节的变量返回
	var digest [Size]byte
	for i, s := range d.s {
		digest[i*4] = byte(s)
		digest[i*4+1] = byte(s >> 8)
		digest[i*4+2] = byte(s >> 16)
		digest[i*4+3] = byte(s >> 24)
	}

	return digest
}

// Sum returns the MD5 checksum of the data.
// [Min] 计算 data 的 MD5 摘要信息
func Sum(data []byte) [Size]byte {
	var d digest
	d.Reset()
	// [Min] 先把能构成分块的数据处理，留下剩余不够分块的数据待处理
	d.Write(data)
	// [Min] 填充分块，处理数据，最后返回消息摘要
	return d.checkSum()
}

```

```go
// Copyright 2013 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// DO NOT EDIT.
// Generate with: go run gen.go -full -output md5block.go

package md5

import (
	"runtime"
	"unsafe"
)

const x86 = runtime.GOARCH == "amd64" || runtime.GOARCH == "386"

var littleEndian bool

// [Min] 判断当前系统的字节序
func init() {
	x := uint32(0x04030201)
	y := [4]byte{0x1, 0x2, 0x3, 0x4}
	littleEndian = *(*[4]byte)(unsafe.Pointer(&x)) == y
}

// [Min] 消息摘要处理函数
func blockGeneric(dig *digest, p []byte) {
	a := dig.s[0]
	b := dig.s[1]
	c := dig.s[2]
	d := dig.s[3]
	var X *[16]uint32
	var xbuf [16]uint32
	// [Min] 这里 p 一定是分块大小的整数倍
	for len(p) >= chunk {
		// [Min] 备份未处理当前分块前的值
		aa, bb, cc, dd := a, b, c, d

		// [Min] 首先根据系统，都按小字节序从 p 中获取一个分块的数据（64字节512位）存入 X
		// [Min] 分成16个小组，每个小组32位
		// This is a constant condition - it is not evaluated on each iteration.
		if x86 {
			// MD5 was designed so that x86 processors can just iterate
			// over the block data directly as uint32s, and we generate
			// less code and run 1.3x faster if we take advantage of that.
			// My apologies.
			X = (*[16]uint32)(unsafe.Pointer(&p[0]))
		} else if littleEndian && uintptr(unsafe.Pointer(&p[0]))&(unsafe.Alignof(uint32(0))-1) == 0 {
			X = (*[16]uint32)(unsafe.Pointer(&p[0]))
		} else {
			X = &xbuf
			j := 0
			for i := 0; i < 16; i++ {
				X[i&15] = uint32(p[j]) | uint32(p[j+1])<<8 | uint32(p[j+2])<<16 | uint32(p[j+3])<<24
				j += 4
			}
        }
            
        // [Min] F(X,Y,Z)=(X&Y)|((~X)&Z) <=>  Z xor (X and (Y xor Z)) 后者更高效
        // [Min] G(X,Y,Z)=(X&Z)|(Y&(~Z)) <=>  Y xor (Z and (X xor Y)) 后者更高效
        // [Min] H(X,Y,Z)=X^Y^Z
        // [Min] I(X,Y,Z)=Y^(X|(~Z))

		// [Min] 设Mj表示消息的第j个子分组（从0到15），<<<s表示循环左移s位，则四种操作为：
		// [Min] FF(a,b,c,d,Mj,s,ti)表示a=b+((a+F(b,c,d)+Mj+ti)<<<s)
		// [Min] GG(a,b,c,d,Mj,s,ti)表示a=b+((a+G(b,c,d)+Mj+ti)<<<s)
		// [Min] HH(a,b,c,d,Mj,s,ti)表示a=b+((a+H(b,c,d)+Mj+ti)<<<s)
		// [Min] II(a,b,c,d,Mj,s,ti)表示a=b+((a+I(b,c,d)+Mj+ti)<<<s)
        
		// [Min] 对每一个分块进行以下4轮计算，每一轮中会对每一小组进行处理
		// Round 1.

		// [Min] FF(a ,b ,c ,d,M0 ,7 ,0xd76aa478 )
		a += (((c ^ d) & b) ^ d) + X[0] + 3614090360
		a = a<<7 | a>>(32-7) + b

		// [Min] FF(d ,a ,b ,c,M1 ,12 ,0xe8c7b756 )
		d += (((b ^ c) & a) ^ c) + X[1] + 3905402710
		d = d<<12 | d>>(32-12) + a

		// [Min] FF(c ,d ,a ,b,M2 ,17 ,0x242070db )
		c += (((a ^ b) & d) ^ b) + X[2] + 606105819
		c = c<<17 | c>>(32-17) + d

		// [Min] FF(b ,c ,d ,a,M3 ,22 ,0xc1bdceee )
		b += (((d ^ a) & c) ^ a) + X[3] + 3250441966
		b = b<<22 | b>>(32-22) + c

		// [Min] FF(a ,b ,c ,d,M4 ,7 ,0xf57c0faf )
		a += (((c ^ d) & b) ^ d) + X[4] + 4118548399
		a = a<<7 | a>>(32-7) + b

		// [Min] b=FF(d,a,b,c,M5,12,0x4787c62a)
		d += (((b ^ c) & a) ^ c) + X[5] + 1200080426
		d = d<<12 | d>>(32-12) + a

		// [Min] c=FF(c,d,a,b,M6,17,0xa8304613)
		c += (((a ^ b) & d) ^ b) + X[6] + 2821735955
		c = c<<17 | c>>(32-17) + d

		// [Min] d=FF(b,c,d,a,M7,22,0xfd469501)
		b += (((d ^ a) & c) ^ a) + X[7] + 4249261313
		b = b<<22 | b>>(32-22) + c

		// [Min] a=FF(a,b,c,d,M8,7,0x698098d8)
		a += (((c ^ d) & b) ^ d) + X[8] + 1770035416
		a = a<<7 | a>>(32-7) + b

		// [Min] b=FF(d,a,b,c,M9,12,0x8b44f7af)
		d += (((b ^ c) & a) ^ c) + X[9] + 2336552879
		d = d<<12 | d>>(32-12) + a

		// [Min] c=FF(c,d,a,b,M10,17,0xffff5bb1)
		c += (((a ^ b) & d) ^ b) + X[10] + 4294925233
		c = c<<17 | c>>(32-17) + d

		// [Min] d=FF(b,c,d,a,M11,22,0x895cd7be)
		b += (((d ^ a) & c) ^ a) + X[11] + 2304563134
		b = b<<22 | b>>(32-22) + c

		// [Min] a=FF(a,b,c,d,M12,7,0x6b901122)
		a += (((c ^ d) & b) ^ d) + X[12] + 1804603682
		a = a<<7 | a>>(32-7) + b

		// [Min] b=FF(d,a,b,c,M13,12,0xfd987193)
		d += (((b ^ c) & a) ^ c) + X[13] + 4254626195
		d = d<<12 | d>>(32-12) + a

		// [Min] c=FF(c,d,a,b,M14,17,0xa679438e)
		c += (((a ^ b) & d) ^ b) + X[14] + 2792965006
		c = c<<17 | c>>(32-17) + d

		// [Min] d=FF(b,c,d,a,M15,22,0x49b40821)
		b += (((d ^ a) & c) ^ a) + X[15] + 1236535329
		b = b<<22 | b>>(32-22) + c

		// Round 2.
		// [Min] a=GG(a,b,c,d,M1,5,0xf61e2562)
		a += (((b ^ c) & d) ^ c) + X[(1+5*0)&15] + 4129170786
		a = a<<5 | a>>(32-5) + b

		// [Min] b=GG(d,a,b,c,M6,9,0xc040b340)
		d += (((a ^ b) & c) ^ b) + X[(1+5*1)&15] + 3225465664
		d = d<<9 | d>>(32-9) + a

		// [Min] c=GG(c,d,a,b,M11,14,0x265e5a51)
		c += (((d ^ a) & b) ^ a) + X[(1+5*2)&15] + 643717713
		c = c<<14 | c>>(32-14) + d

		// [Min] d=GG(b,c,d,a,M0,20,0xe9b6c7aa)
		b += (((c ^ d) & a) ^ d) + X[(1+5*3)&15] + 3921069994
		b = b<<20 | b>>(32-20) + c

		// [Min] a=GG(a,b,c,d,M5,5,0xd62f105d)
		a += (((b ^ c) & d) ^ c) + X[(1+5*4)&15] + 3593408605
		a = a<<5 | a>>(32-5) + b

		// [Min] b=GG(d,a,b,c,M10,9,0x02441453)
		d += (((a ^ b) & c) ^ b) + X[(1+5*5)&15] + 38016083
		d = d<<9 | d>>(32-9) + a

		// [Min] c=GG(c,d,a,b,M15,14,0xd8a1e681)
		c += (((d ^ a) & b) ^ a) + X[(1+5*6)&15] + 3634488961
		c = c<<14 | c>>(32-14) + d

		// [Min] d=GG(b,c,d,a,M4,20,0xe7d3fbc8)
		b += (((c ^ d) & a) ^ d) + X[(1+5*7)&15] + 3889429448
		b = b<<20 | b>>(32-20) + c

		// [Min] a=GG(a,b,c,d,M9,5,0x21e1cde6)
		a += (((b ^ c) & d) ^ c) + X[(1+5*8)&15] + 568446438
		a = a<<5 | a>>(32-5) + b

		// [Min] b=GG(d,a,b,c,M14,9,0xc33707d6)
		d += (((a ^ b) & c) ^ b) + X[(1+5*9)&15] + 3275163606
		d = d<<9 | d>>(32-9) + a

		// [Min] c=GG(c,d,a,b,M3,14,0xf4d50d87)
		c += (((d ^ a) & b) ^ a) + X[(1+5*10)&15] + 4107603335
		c = c<<14 | c>>(32-14) + d

		// [Min] d=GG(b,c,d,a,M8,20,0x455a14ed)
		b += (((c ^ d) & a) ^ d) + X[(1+5*11)&15] + 1163531501
		b = b<<20 | b>>(32-20) + c

		// [Min] a=GG(a,b,c,d,M13,5,0xa9e3e905)
		a += (((b ^ c) & d) ^ c) + X[(1+5*12)&15] + 2850285829
		a = a<<5 | a>>(32-5) + b

		// [Min] b=GG(d,a,b,c,M2,9,0xfcefa3f8)
		d += (((a ^ b) & c) ^ b) + X[(1+5*13)&15] + 4243563512
		d = d<<9 | d>>(32-9) + a

		// [Min] c=GG(c,d,a,b,M7,14,0x676f02d9)
		c += (((d ^ a) & b) ^ a) + X[(1+5*14)&15] + 1735328473
		c = c<<14 | c>>(32-14) + d

		// [Min] d=GG(b,c,d,a,M12,20,0x8d2a4c8a)
		b += (((c ^ d) & a) ^ d) + X[(1+5*15)&15] + 2368359562
		b = b<<20 | b>>(32-20) + c

		// Round 3.
		// [Min] a=HH(a,b,c,d,M5,4,0xfffa3942)
		a += (b ^ c ^ d) + X[(5+3*0)&15] + 4294588738
		a = a<<4 | a>>(32-4) + b

		// [Min] b=HH(d,a,b,c,M8,11,0x8771f681)
		d += (a ^ b ^ c) + X[(5+3*1)&15] + 2272392833
		d = d<<11 | d>>(32-11) + a

		// [Min] c=HH(c,d,a,b,M11,16,0x6d9d6122)
		c += (d ^ a ^ b) + X[(5+3*2)&15] + 1839030562
		c = c<<16 | c>>(32-16) + d

		// [Min] d=HH(b,c,d,a,M14,23,0xfde5380c)
		b += (c ^ d ^ a) + X[(5+3*3)&15] + 4259657740
		b = b<<23 | b>>(32-23) + c

		// [Min] a=HH(a,b,c,d,M1,4,0xa4beea44)
		a += (b ^ c ^ d) + X[(5+3*4)&15] + 2763975236
		a = a<<4 | a>>(32-4) + b

		// [Min] b=HH(d,a,b,c,M4,11,0x4bdecfa9)
		d += (a ^ b ^ c) + X[(5+3*5)&15] + 1272893353
		d = d<<11 | d>>(32-11) + a

		// [Min] c=HH(c,d,a,b,M7,16,0xf6bb4b60)
		c += (d ^ a ^ b) + X[(5+3*6)&15] + 4139469664
		c = c<<16 | c>>(32-16) + d

		// [Min] d=HH(b,c,d,a,M10,23,0xbebfbc70)
		b += (c ^ d ^ a) + X[(5+3*7)&15] + 3200236656
		b = b<<23 | b>>(32-23) + c

		// [Min] a=HH(a,b,c,d,M13,4,0x289b7ec6)
		a += (b ^ c ^ d) + X[(5+3*8)&15] + 681279174
		a = a<<4 | a>>(32-4) + b

		// [Min] b=HH(d,a,b,c,M0,11,0xeaa127fa)
		d += (a ^ b ^ c) + X[(5+3*9)&15] + 3936430074
		d = d<<11 | d>>(32-11) + a

		// [Min] c=HH(c,d,a,b,M3,16,0xd4ef3085)
		c += (d ^ a ^ b) + X[(5+3*10)&15] + 3572445317
		c = c<<16 | c>>(32-16) + d

		// [Min] d=HH(b,c,d,a,M6,23,0x04881d05)
		b += (c ^ d ^ a) + X[(5+3*11)&15] + 76029189
		b = b<<23 | b>>(32-23) + c

		// [Min] a=HH(a,b,c,d,M9,4,0xd9d4d039)
		a += (b ^ c ^ d) + X[(5+3*12)&15] + 3654602809
		a = a<<4 | a>>(32-4) + b

		// [Min] b=HH(d,a,b,c,M12,11,0xe6db99e5)
		d += (a ^ b ^ c) + X[(5+3*13)&15] + 3873151461
		d = d<<11 | d>>(32-11) + a

		// [Min] c=HH(c,d,a,b,M15,16,0x1fa27cf8)
		c += (d ^ a ^ b) + X[(5+3*14)&15] + 530742520
		c = c<<16 | c>>(32-16) + d

		// [Min] d=HH(b,c,d,a,M2,23,0xc4ac5665)
		b += (c ^ d ^ a) + X[(5+3*15)&15] + 3299628645
		b = b<<23 | b>>(32-23) + c

		// Round 4.

		// [Min] a=II(a,b,c,d,M0,6,0xf4292244)

		a += (c ^ (b | ^d)) + X[(7*0)&15] + 4096336452
		a = a<<6 | a>>(32-6) + b

		// [Min] b=II(d,a,b,c,M7,10,0x432aff97)
		d += (b ^ (a | ^c)) + X[(7*1)&15] + 1126891415
		d = d<<10 | d>>(32-10) + a

		// [Min] c=II(c,d,a,b,M14,15,0xab9423a7)
		c += (a ^ (d | ^b)) + X[(7*2)&15] + 2878612391
		c = c<<15 | c>>(32-15) + d

		// [Min] d=II(b,c,d,a,M5,21,0xfc93a039)
		b += (d ^ (c | ^a)) + X[(7*3)&15] + 4237533241
		b = b<<21 | b>>(32-21) + c

		// [Min] a=II(a,b,c,d,M12,6,0x655b59c3)
		a += (c ^ (b | ^d)) + X[(7*4)&15] + 1700485571
		a = a<<6 | a>>(32-6) + b

		// [Min] b=II(d,a,b,c,M3,10,0x8f0ccc92)
		d += (b ^ (a | ^c)) + X[(7*5)&15] + 2399980690
		d = d<<10 | d>>(32-10) + a

		// [Min] c=II(c,d,a,b,M10,15,0xffeff47d)
		c += (a ^ (d | ^b)) + X[(7*6)&15] + 4293915773
		c = c<<15 | c>>(32-15) + d

		// [Min] d=II(b,c,d,a,M1,21,0x85845dd1)
		b += (d ^ (c | ^a)) + X[(7*7)&15] + 2240044497
		b = b<<21 | b>>(32-21) + c

		// [Min] a=II(a,b,c,d,M8,6,0x6fa87e4f)
		a += (c ^ (b | ^d)) + X[(7*8)&15] + 1873313359
		a = a<<6 | a>>(32-6) + b

		// [Min] b=II(d,a,b,c,M15,10,0xfe2ce6e0)
		d += (b ^ (a | ^c)) + X[(7*9)&15] + 4264355552
		d = d<<10 | d>>(32-10) + a

		// [Min] c=II(c,d,a,b,M6,15,0xa3014314)
		c += (a ^ (d | ^b)) + X[(7*10)&15] + 2734768916
		c = c<<15 | c>>(32-15) + d

		// [Min] d=II(b,c,d,a,M13,21,0x4e0811a1)
		b += (d ^ (c | ^a)) + X[(7*11)&15] + 1309151649
		b = b<<21 | b>>(32-21) + c

		// [Min] a=II(a,b,c,d,M4,6,0xf7537e82)
		a += (c ^ (b | ^d)) + X[(7*12)&15] + 4149444226
		a = a<<6 | a>>(32-6) + b

		// [Min] b=II(d,a,b,c,M11,10,0xbd3af235)
		d += (b ^ (a | ^c)) + X[(7*13)&15] + 3174756917
		d = d<<10 | d>>(32-10) + a

		// [Min] c=II(c,d,a,b,M2,15,0x2ad7d2bb)
		c += (a ^ (d | ^b)) + X[(7*14)&15] + 718787259
		c = c<<15 | c>>(32-15) + d

		// [Min] d=II(b,c,d,a,M9,21,0xeb86d391)
		b += (d ^ (c | ^a)) + X[(7*15)&15] + 3951481745
		b = b<<21 | b>>(32-21) + c

		// [Min] 在原来的基础上加上经过4轮计算后的值
		a += aa
		b += bb
		c += cc
		d += dd

		// [Min] 处理下一分块
		p = p[chunk:]
	}

	// [Min] 设置最终摘要
	dig.s[0] = a
	dig.s[1] = b
	dig.s[2] = c
	dig.s[3] = d
}

```

# 3. SHA1

## 3.1 与 MD5 的比较
- SHA1 摘要长度为20字节160位长
- SHA1 与 MD5 相反，采用大字节序存储数值
- SHA1 采用与 MD5 完全一致的分块方式
- SHA1 块内按大字节序分为16组 uint32，再进行共计80次循环计算

## 3.2 SHA1 分块处理算法

https://en.wikipedia.org/wiki/SHA-1

## 3.3 Go源码分析

| |
|:---|
|[sha1.go](https://github.com/mooncaker816/LearningGoStandardLib/blob/master/crypto/sha1/sha1.go)|
|[sha1block.go](https://github.com/mooncaker816/LearningGoStandardLib/blob/master/crypto/sha1/sha1block.go)|

# 4. SHA2

　　1. SHA2 是 SHA256，SHA224，SHA512，SHA384，SHA512-256，SHA512-224 的统称  

　　2. SHA224 可以看成是以不同初始摘要计算的 SHA256 的截取

　　3. 同样，SHA384，SHA512-256，SHA512-224 可以看成是以不同初始摘要计算的 SHA512 的截取　

## 4.1 SHA256，SHA224

### 4.1.1 与 MD5 的比较
- SHA256 摘要长度为32字节256位长
- SHA256 与 MD5 相反，采用大字节序存储数值
- SHA256 采用与 MD5 完全一致的分块方式
- SHA256 块内按大字节序分为16组 uint32，再以这16组数据为基础，按一定算法扩充至64组，最后再进行共计64次循环计算

### 4.1.2 SHA256 分块处理算法

https://en.wikipedia.org/wiki/SHA-2

### 4.1.3 Go源码分析

| |
|:---|
|[sha256.go](https://github.com/mooncaker816/LearningGoStandardLib/blob/master/crypto/sha256/sha256.go)|
|[sha256block.go](https://github.com/mooncaker816/LearningGoStandardLib/blob/master/crypto/sha256/sha256block.go)|

## 4.2 SHA512，SHA384，SHA512-256，SHA512-224

### 4.2.1 与 MD5 的比较
- SHA512 摘要长度为64字节512位长
- SHA512 与 MD5 相反，采用大字节序存储数值
- SHA512 采用与 MD5 基本一致的分块方式，分块大小略有调整
	分块大小由64字节512位变为128字节1024位，
	最后一个分块末尾用来记录源数据字节长度的部分由8字节改为16字节
	因为分块的长度改成了128字节，所以填充临界点位128-16=112字节
- SHA512 块内按大字节序分为16组 uint64，再以这16组数据为基础，按一定算法扩充至80组，最后再进行共计80次循环计算

### 4.2.2 SHA512 分块处理算法

https://en.wikipedia.org/wiki/SHA-2

### 4.2.3 Go源码分析

| |
|:---|
|[sha512.go](https://github.com/mooncaker816/LearningGoStandardLib/blob/master/crypto/sha512/sha512.go)|
|[sha512block.go](https://github.com/mooncaker816/LearningGoStandardLib/blob/master/crypto/sha512/sha512block.go)|
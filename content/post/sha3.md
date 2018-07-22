+++
title = "SHA3"
date = 2018-07-21T08:52:27+08:00
draft = false

# Tags and categories
# For example, use `tags = []` for no tags, or the form `tags = ["A Tag", "Another Tag"]` for one or more tags.
tags = ["SHA3"]
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

# 1 什么是SHA-3

　　SHA-3是一种作为新标准发布的单向散列函数算法，用来替代在理论上已被找出攻击方法的SHA-1算法。全世界的企业和密码学家提交了很多SHA-3的候选方案，经过长达5年的选拔，最终于2012年正式确定将Kececak算法作为SHA-3标准。  
　　Keccak的以下几大特点，是其成为SHA-3标准的重要原因：

- 采用了与SHA-2完全不同的结构
- 结构清晰，易于分析
- 能够适用于各种设备，也适用于嵌入式应用
- 在硬件上的实现显示出了很高的性能
- 比其他最终候选算法安全性边际更大

　　Keccak可以生成任意长度的散列值，但为了配合SHA-2的散列值长度，SHA-3标准中共规定了SHA3-224，SHA3-256，SHA3-384，SHA3-512这4种版本。在输入数据的长度上限方面，SHA-1为2^64 - 1，SHA-2为2^128 - 1，而SHA-3则没有长度限制。  
　　此外，SHA3还有两个可以输出任意长度散列值的函数：SHAKE128,SHAKE256，在 Go 的SHA3文档中，推荐使用SHAKE256。  

> // Guidance  
//  
// If you aren't sure what function you need, use SHAKE256 with at least 64  
// bytes of output. The SHAKE instances are faster than the SHA3 instances;  
// the latter have to allocate memory to conform to the hash.Hash interface.  
//  
// If you need a secret-key MAC (message authentication code), prepend the  
// secret key to the input, hash with SHAKE256 and read at least 32 bytes of  
// output.  

# 2 Keccak

## 2.1 Keccak的结构

　　Keccak采用了与SHA-1，SHA-2完全不同的海绵结构。顾名思义，海绵最大的特点就是其吸水性，用在此处想必也是有此寓意。在Keccak的海绵结构中，输入数据在进行分组以及相应的填充之后，要经过吸收阶段和挤出阶段，最终生成输出的散列值。  
　　吸收阶段中，源数据按一定大小分组，最后一组会进行填充补足。依次将每一分组的数据与Keccak中内部状态作XOR操作，从而将分组数据吸收入Keccak结构中，再将XOR之后的数据按一定算法进行搅拌，此时内部状态中的数据为该分组数据搅拌后的数据，再在此状态下用相同的方法吸入下一组数据并再次搅拌，循环往复，直至最后一组数据搅拌成功，完成吸收阶段。  
　　挤出阶段中，在完成对最后一组数据的搅拌后，直接按分组大小将内部状态中的数据输出到最终输出中，如果达不到输出的长度要求，则再次执行同样的搅拌，每次从内部状态中挤出最多分组大小的数据，循环往复，直至达到输出长度的要求。  

![Keccak 结构流程图](http://oumnldfwl.bkt.clouddn.com/keccak结构流程图.png)

## 2.2 Keccak的内部状态

　　Keccak的内部状态可以看成是一个5*5*w的三维立方体，每一个单位元素代表一个比特位。根据设计规格，Keccak的内部状态大小可以为25，50，100，200，400，800，1600共7种，分别对应的w为1，2，4，8，16，32，64。SHA3 采用了最大的规格，用以提升安全等级，所以SHA3的内部状态实际是一个5*5*64大小的比特流。将这个比特流映射到具体的数据结构上，可以表述为一个由25个无符号64位整数组成的数组。  
　　更具体的内部状态信息，可以参考以下官方文档中的3.1小节。
https://csrc.nist.gov/csrc/media/publications/fips/202/final/documents/fips_202_draft.pdf

## 2.3 搅拌方法

　　Keccak最重要的就是他的“搅拌函数”，用来在原数据的基础上对其进行一系列复杂的运算，最后生成摘要信息。搅拌的过程一共可以分为5个步骤，θ，ρ，π，χ，ι，共计24轮计算。每一个步骤都是对这个5*5*64的状态矩阵进行相应的计算，移位，旋转等操作。
　　具体步骤可以参考上文链接中的3.2小节，此处不再赘述。

## 2.4 搅拌方法的实现

　　在Keccak官网上，给出了许多有趣的实现方法，以下是参考链接：
https://keccak.team/files/Keccak-implementation-3.2.pdf  
而 Go 的 x/crypto/sha3 包采用的是其中的 Efficient in-place implementations。

```go
// Copyright 2014 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

//  +build !amd64 appengine gccgo

package sha3

// rc stores the round constants for use in the ι step.
var rc = [24]uint64{
	0x0000000000000001,
	0x0000000000008082,
	0x800000000000808A,
	0x8000000080008000,
	0x000000000000808B,
	0x0000000080000001,
	0x8000000080008081,
	0x8000000000008009,
	0x000000000000008A,
	0x0000000000000088,
	0x0000000080008009,
	0x000000008000000A,
	0x000000008000808B,
	0x800000000000008B,
	0x8000000000008089,
	0x8000000000008003,
	0x8000000000008002,
	0x8000000000000080,
	0x000000000000800A,
	0x800000008000000A,
	0x8000000080008081,
	0x8000000000008080,
	0x0000000080000001,
	0x8000000080008008,
}

// keccakF1600 applies the Keccak permutation to a 1600b-wide
// state represented as a slice of 25 uint64s.
// [Min] 对已经吸收到 a 中的一个分组的数据进行处理
func keccakF1600(a *[25]uint64) {
	// Implementation translated from Keccak-inplace.c
	// in the keccak reference code.
	var t, bc0, bc1, bc2, bc3, bc4, d0, d1, d2, d3, d4 uint64

	/* [Min]
		共计24轮计算，每四轮一循环，所有涉及A,B,C,D索引的计算都是mod 5，对a的索引计算都是 mod 25
	已知	N = 1 0
				1 2
	N^i的值每4轮一循环（元素值 mod5 相同）
	A[x,y] = a[5y+x], 此处小a就是函数的输入
	r[x,y] 值如下表，代表循环左移的位数
		x=3 x=4 x=0 x=1 x=2
	y=2 25	39  3   10  43
	y=1 55  20  36  44  6
	y=0 28  27  0   1   62
	y=4 56  14  18  2   61
	y=3 21  8   41  45  15

		对第i轮进行计算：
		1. C[x] = A[N^i(x,0)T]⊕A[N^i(x,1)T]⊕A[N^i(x,2)T]⊕A[N^i(x,3)T]⊕A[N^i(x,4)T], x = 0...4
		2. D[x] = C[x−1]⊕ROT(C[x+1],1), x = 0...4
		for y=0...4
		3. B[x+2y] = ROT((A[N^(i+1)(x,y)T]⊕D[x]),r[N(x,y)T]), x=0...4
		4. A[N^(i+1)(x,y)T]=B[x]⊕((NOT B[x+1]) AND B[x+2]), x=0...4
		end
		5. A[0,0] = A[0,0] ⊕ RC[i]
	*/
	for i := 0; i < 24; i += 4 {
		// Combines the 5 steps in each round into 2 steps.
		// Unrolls 4 rounds per loop and spreads some steps across rounds.

		// Round 1
		/* [Min]
		i = 0, N^0 = 单位矩阵
		C[0] = A[0,0]⊕A[0,1]⊕A[0,2]⊕A[0,3]⊕A[0,4]
		     = a[0] ^ a[5] ^ a[10] ^ a[15] ^ a[20]
		C[1] = A[1,0]⊕A[1,1]⊕A[1,2]⊕A[1,3]⊕A[1,4]
			 = a[1] ^ a[6] ^ a[11] ^ a[16] ^ a[21]
		...
		*/
		// [Min] C[x] = A[N^i(x,0)T]⊕A[N^i(x,1)T]⊕A[N^i(x,2)T]⊕A[N^i(x,3)T]⊕A[N^i(x,4)T]
		bc0 = a[0] ^ a[5] ^ a[10] ^ a[15] ^ a[20]
		bc1 = a[1] ^ a[6] ^ a[11] ^ a[16] ^ a[21]
		bc2 = a[2] ^ a[7] ^ a[12] ^ a[17] ^ a[22]
		bc3 = a[3] ^ a[8] ^ a[13] ^ a[18] ^ a[23]
		bc4 = a[4] ^ a[9] ^ a[14] ^ a[19] ^ a[24]
		// [Min] D[x] = C[x−1]⊕ROT(C[x+1],1), x = 0...4
		d0 = bc4 ^ (bc1<<1 | bc1>>63)
		d1 = bc0 ^ (bc2<<1 | bc2>>63)
		d2 = bc1 ^ (bc3<<1 | bc3>>63)
		d3 = bc2 ^ (bc4<<1 | bc4>>63)
		d4 = bc3 ^ (bc0<<1 | bc0>>63)

		// [Min] y = 0
		// [Min]    B[x+2y] = ROT((A[N^(i+1)(x,y)T]⊕D[x]),r[N(x,y)T]), x=0...4
		// [Min]    A[N^(i+1)(x,y)T]=B[x]⊕((NOT B[x+1]) AND B[x+2]), x=0...4
		// [Min] A[0,0] = A[0,0] ⊕ RC[i]
		bc0 = a[0] ^ d0
		t = a[6] ^ d1
		bc1 = t<<44 | t>>(64-44)
		t = a[12] ^ d2
		bc2 = t<<43 | t>>(64-43)
		t = a[18] ^ d3
		bc3 = t<<21 | t>>(64-21)
		t = a[24] ^ d4
		bc4 = t<<14 | t>>(64-14)
		a[0] = bc0 ^ (bc2 &^ bc1) ^ rc[i]
		a[6] = bc1 ^ (bc3 &^ bc2)
		a[12] = bc2 ^ (bc4 &^ bc3)
		a[18] = bc3 ^ (bc0 &^ bc4)
		a[24] = bc4 ^ (bc1 &^ bc0)

		// [Min] y = 1
		// [Min]    B[x+2y] = ROT((A[N^(i+1)(x,y)T]⊕D[x]),r[N(x,y)T]), x=0...4
		// [Min]    A[N^(i+1)(x,y)T]=B[x]⊕((NOT B[x+1]) AND B[x+2]), x=0...4
		t = a[10] ^ d0
		bc2 = t<<3 | t>>(64-3)
		t = a[16] ^ d1
		bc3 = t<<45 | t>>(64-45)
		t = a[22] ^ d2
		bc4 = t<<61 | t>>(64-61)
		t = a[3] ^ d3
		bc0 = t<<28 | t>>(64-28)
		t = a[9] ^ d4
		bc1 = t<<20 | t>>(64-20)
		a[10] = bc0 ^ (bc2 &^ bc1)
		a[16] = bc1 ^ (bc3 &^ bc2)
		a[22] = bc2 ^ (bc4 &^ bc3)
		a[3] = bc3 ^ (bc0 &^ bc4)
		a[9] = bc4 ^ (bc1 &^ bc0)

		// [Min] y = 2
		// [Min]    B[x+2y] = ROT((A[N^(i+1)(x,y)T]⊕D[x]),r[N(x,y)T]), x=0...4
		// [Min]    A[N^(i+1)(x,y)T]=B[x]⊕((NOT B[x+1]) AND B[x+2]), x=0...4
		t = a[20] ^ d0
		bc4 = t<<18 | t>>(64-18)
		t = a[1] ^ d1
		bc0 = t<<1 | t>>(64-1)
		t = a[7] ^ d2
		bc1 = t<<6 | t>>(64-6)
		t = a[13] ^ d3
		bc2 = t<<25 | t>>(64-25)
		t = a[19] ^ d4
		bc3 = t<<8 | t>>(64-8)
		a[20] = bc0 ^ (bc2 &^ bc1)
		a[1] = bc1 ^ (bc3 &^ bc2)
		a[7] = bc2 ^ (bc4 &^ bc3)
		a[13] = bc3 ^ (bc0 &^ bc4)
		a[19] = bc4 ^ (bc1 &^ bc0)

		// [Min] y = 3
		// [Min]    B[x+2y] = ROT((A[N^(i+1)(x,y)T]⊕D[x]),r[N(x,y)T]), x=0...4
		// [Min]    A[N^(i+1)(x,y)T]=B[x]⊕((NOT B[x+1]) AND B[x+2]), x=0...4
		t = a[5] ^ d0
		bc1 = t<<36 | t>>(64-36)
		t = a[11] ^ d1
		bc2 = t<<10 | t>>(64-10)
		t = a[17] ^ d2
		bc3 = t<<15 | t>>(64-15)
		t = a[23] ^ d3
		bc4 = t<<56 | t>>(64-56)
		t = a[4] ^ d4
		bc0 = t<<27 | t>>(64-27)
		a[5] = bc0 ^ (bc2 &^ bc1)
		a[11] = bc1 ^ (bc3 &^ bc2)
		a[17] = bc2 ^ (bc4 &^ bc3)
		a[23] = bc3 ^ (bc0 &^ bc4)
		a[4] = bc4 ^ (bc1 &^ bc0)

		// [Min] y = 4
		// [Min]    B[x+2y] = ROT((A[N^(i+1)(x,y)T]⊕D[x]),r[N(x,y)T]), x=0...4
		// [Min]    A[N^(i+1)(x,y)T]=B[x]⊕((NOT B[x+1]) AND B[x+2]), x=0...4
		t = a[15] ^ d0
		bc3 = t<<41 | t>>(64-41)
		t = a[21] ^ d1
		bc4 = t<<2 | t>>(64-2)
		t = a[2] ^ d2
		bc0 = t<<62 | t>>(64-62)
		t = a[8] ^ d3
		bc1 = t<<55 | t>>(64-55)
		t = a[14] ^ d4
		bc2 = t<<39 | t>>(64-39)
		a[15] = bc0 ^ (bc2 &^ bc1)
		a[21] = bc1 ^ (bc3 &^ bc2)
		a[2] = bc2 ^ (bc4 &^ bc3)
		a[8] = bc3 ^ (bc0 &^ bc4)
		a[14] = bc4 ^ (bc1 &^ bc0)

		// Round 2
		/* [Min]
		i = 1, N^i将 (x,y) 映射成 (x,x+2y)
		C[0] = A[0,0]⊕A[0,2]⊕A[0,4]⊕A[0,1]⊕A[0,3]
		     = a[0] ^ a[10] ^ a[20] ^ a[5] ^ a[15]
		C[1] = A[1,1]⊕A[1,3]⊕A[1,0]⊕A[1,2]⊕A[1,4]
			 = a[6] ^ a[16] ^ a[1] ^ a[11] ^ a[21]
		...
		*/
		// [Min] C[x] = A[N^i(x,0)T]⊕A[N^i(x,1)T]⊕A[N^i(x,2)T]⊕A[N^i(x,3)T]⊕A[N^i(x,4)T]
		bc0 = a[0] ^ a[5] ^ a[10] ^ a[15] ^ a[20]
		bc1 = a[1] ^ a[6] ^ a[11] ^ a[16] ^ a[21]
		bc2 = a[2] ^ a[7] ^ a[12] ^ a[17] ^ a[22]
		bc3 = a[3] ^ a[8] ^ a[13] ^ a[18] ^ a[23]
		bc4 = a[4] ^ a[9] ^ a[14] ^ a[19] ^ a[24]
		// [Min] D[x] = C[x−1]⊕ROT(C[x+1],1), x = 0...4
		d0 = bc4 ^ (bc1<<1 | bc1>>63)
		d1 = bc0 ^ (bc2<<1 | bc2>>63)
		d2 = bc1 ^ (bc3<<1 | bc3>>63)
		d3 = bc2 ^ (bc4<<1 | bc4>>63)
		d4 = bc3 ^ (bc0<<1 | bc0>>63)

		// [Min] y = 0
		// [Min]    B[x+2y] = ROT((A[N^(i+1)(x,y)T]⊕D[x]),r[N(x,y)T]), x=0...4
		// [Min]    A[N^(i+1)(x,y)T]=B[x]⊕((NOT B[x+1]) AND B[x+2]), x=0...4
		// [Min] A[0,0] = A[0,0] ⊕ RC[i]
		bc0 = a[0] ^ d0
		t = a[16] ^ d1
		bc1 = t<<44 | t>>(64-44)
		t = a[7] ^ d2
		bc2 = t<<43 | t>>(64-43)
		t = a[23] ^ d3
		bc3 = t<<21 | t>>(64-21)
		t = a[14] ^ d4
		bc4 = t<<14 | t>>(64-14)
		a[0] = bc0 ^ (bc2 &^ bc1) ^ rc[i+1]
		a[16] = bc1 ^ (bc3 &^ bc2)
		a[7] = bc2 ^ (bc4 &^ bc3)
		a[23] = bc3 ^ (bc0 &^ bc4)
		a[14] = bc4 ^ (bc1 &^ bc0)

		// [Min] y = 1
		// [Min]    B[x+2y] = ROT((A[N^(i+1)(x,y)T]⊕D[x]),r[N(x,y)T]), x=0...4
		// [Min]    A[N^(i+1)(x,y)T]=B[x]⊕((NOT B[x+1]) AND B[x+2]), x=0...4
		t = a[20] ^ d0
		bc2 = t<<3 | t>>(64-3)
		t = a[11] ^ d1
		bc3 = t<<45 | t>>(64-45)
		t = a[2] ^ d2
		bc4 = t<<61 | t>>(64-61)
		t = a[18] ^ d3
		bc0 = t<<28 | t>>(64-28)
		t = a[9] ^ d4
		bc1 = t<<20 | t>>(64-20)
		a[20] = bc0 ^ (bc2 &^ bc1)
		a[11] = bc1 ^ (bc3 &^ bc2)
		a[2] = bc2 ^ (bc4 &^ bc3)
		a[18] = bc3 ^ (bc0 &^ bc4)
		a[9] = bc4 ^ (bc1 &^ bc0)

		// [Min] y = 2
		// [Min]    B[x+2y] = ROT((A[N^(i+1)(x,y)T]⊕D[x]),r[N(x,y)T]), x=0...4
		// [Min]    A[N^(i+1)(x,y)T]=B[x]⊕((NOT B[x+1]) AND B[x+2]), x=0...4
		t = a[15] ^ d0
		bc4 = t<<18 | t>>(64-18)
		t = a[6] ^ d1
		bc0 = t<<1 | t>>(64-1)
		t = a[22] ^ d2
		bc1 = t<<6 | t>>(64-6)
		t = a[13] ^ d3
		bc2 = t<<25 | t>>(64-25)
		t = a[4] ^ d4
		bc3 = t<<8 | t>>(64-8)
		a[15] = bc0 ^ (bc2 &^ bc1)
		a[6] = bc1 ^ (bc3 &^ bc2)
		a[22] = bc2 ^ (bc4 &^ bc3)
		a[13] = bc3 ^ (bc0 &^ bc4)
		a[4] = bc4 ^ (bc1 &^ bc0)

		// [Min] y = 3
		// [Min]    B[x+2y] = ROT((A[N^(i+1)(x,y)T]⊕D[x]),r[N(x,y)T]), x=0...4
		// [Min]    A[N^(i+1)(x,y)T]=B[x]⊕((NOT B[x+1]) AND B[x+2]), x=0...4
		t = a[10] ^ d0
		bc1 = t<<36 | t>>(64-36)
		t = a[1] ^ d1
		bc2 = t<<10 | t>>(64-10)
		t = a[17] ^ d2
		bc3 = t<<15 | t>>(64-15)
		t = a[8] ^ d3
		bc4 = t<<56 | t>>(64-56)
		t = a[24] ^ d4
		bc0 = t<<27 | t>>(64-27)
		a[10] = bc0 ^ (bc2 &^ bc1)
		a[1] = bc1 ^ (bc3 &^ bc2)
		a[17] = bc2 ^ (bc4 &^ bc3)
		a[8] = bc3 ^ (bc0 &^ bc4)
		a[24] = bc4 ^ (bc1 &^ bc0)

		// [Min] y = 4
		// [Min]    B[x+2y] = ROT((A[N^(i+1)(x,y)T]⊕D[x]),r[N(x,y)T]), x=0...4
		// [Min]    A[N^(i+1)(x,y)T]=B[x]⊕((NOT B[x+1]) AND B[x+2]), x=0...4
		t = a[5] ^ d0
		bc3 = t<<41 | t>>(64-41)
		t = a[21] ^ d1
		bc4 = t<<2 | t>>(64-2)
		t = a[12] ^ d2
		bc0 = t<<62 | t>>(64-62)
		t = a[3] ^ d3
		bc1 = t<<55 | t>>(64-55)
		t = a[19] ^ d4
		bc2 = t<<39 | t>>(64-39)
		a[5] = bc0 ^ (bc2 &^ bc1)
		a[21] = bc1 ^ (bc3 &^ bc2)
		a[12] = bc2 ^ (bc4 &^ bc3)
		a[3] = bc3 ^ (bc0 &^ bc4)
		a[19] = bc4 ^ (bc1 &^ bc0)

		// Round 3
		/* [Min]
		i = 2, N^i将 (x,y) 映射成 (x,3x+4y)
		C[0] = A[0,0]⊕A[0,4]⊕A[0,3]⊕A[0,2]⊕A[0,1]
		     = a[0] ^ a[20] ^ a[15] ^ a[10] ^ a[5]
		C[1] = A[1,3]⊕A[1,2]⊕A[1,1]⊕A[1,0]⊕A[1,4]
			 = a[16] ^ a[11] ^ a[6] ^ a[1] ^ a[21]
		...
		*/
		// [Min] C[x] = A[N^i(x,0)T]⊕A[N^i(x,1)T]⊕A[N^i(x,2)T]⊕A[N^i(x,3)T]⊕A[N^i(x,4)T]
		bc0 = a[0] ^ a[5] ^ a[10] ^ a[15] ^ a[20]
		bc1 = a[1] ^ a[6] ^ a[11] ^ a[16] ^ a[21]
		bc2 = a[2] ^ a[7] ^ a[12] ^ a[17] ^ a[22]
		bc3 = a[3] ^ a[8] ^ a[13] ^ a[18] ^ a[23]
		bc4 = a[4] ^ a[9] ^ a[14] ^ a[19] ^ a[24]
		// [Min] D[x] = C[x−1]⊕ROT(C[x+1],1), x = 0...4
		d0 = bc4 ^ (bc1<<1 | bc1>>63)
		d1 = bc0 ^ (bc2<<1 | bc2>>63)
		d2 = bc1 ^ (bc3<<1 | bc3>>63)
		d3 = bc2 ^ (bc4<<1 | bc4>>63)
		d4 = bc3 ^ (bc0<<1 | bc0>>63)

		// [Min] y = 0
		// [Min]    B[x+2y] = ROT((A[N^(i+1)(x,y)T]⊕D[x]),r[N(x,y)T]), x=0...4
		// [Min]    A[N^(i+1)(x,y)T]=B[x]⊕((NOT B[x+1]) AND B[x+2]), x=0...4
		// [Min] A[0,0] = A[0,0] ⊕ RC[i]
		bc0 = a[0] ^ d0
		t = a[11] ^ d1
		bc1 = t<<44 | t>>(64-44)
		t = a[22] ^ d2
		bc2 = t<<43 | t>>(64-43)
		t = a[8] ^ d3
		bc3 = t<<21 | t>>(64-21)
		t = a[19] ^ d4
		bc4 = t<<14 | t>>(64-14)
		a[0] = bc0 ^ (bc2 &^ bc1) ^ rc[i+2]
		a[11] = bc1 ^ (bc3 &^ bc2)
		a[22] = bc2 ^ (bc4 &^ bc3)
		a[8] = bc3 ^ (bc0 &^ bc4)
		a[19] = bc4 ^ (bc1 &^ bc0)

		// [Min] y = 1
		// [Min]    B[x+2y] = ROT((A[N^(i+1)(x,y)T]⊕D[x]),r[N(x,y)T]), x=0...4
		// [Min]    A[N^(i+1)(x,y)T]=B[x]⊕((NOT B[x+1]) AND B[x+2]), x=0...4
		t = a[15] ^ d0
		bc2 = t<<3 | t>>(64-3)
		t = a[1] ^ d1
		bc3 = t<<45 | t>>(64-45)
		t = a[12] ^ d2
		bc4 = t<<61 | t>>(64-61)
		t = a[23] ^ d3
		bc0 = t<<28 | t>>(64-28)
		t = a[9] ^ d4
		bc1 = t<<20 | t>>(64-20)
		a[15] = bc0 ^ (bc2 &^ bc1)
		a[1] = bc1 ^ (bc3 &^ bc2)
		a[12] = bc2 ^ (bc4 &^ bc3)
		a[23] = bc3 ^ (bc0 &^ bc4)
		a[9] = bc4 ^ (bc1 &^ bc0)

		// [Min] y = 2
		// [Min]    B[x+2y] = ROT((A[N^(i+1)(x,y)T]⊕D[x]),r[N(x,y)T]), x=0...4
		// [Min]    A[N^(i+1)(x,y)T]=B[x]⊕((NOT B[x+1]) AND B[x+2]), x=0...4
		t = a[5] ^ d0
		bc4 = t<<18 | t>>(64-18)
		t = a[16] ^ d1
		bc0 = t<<1 | t>>(64-1)
		t = a[2] ^ d2
		bc1 = t<<6 | t>>(64-6)
		t = a[13] ^ d3
		bc2 = t<<25 | t>>(64-25)
		t = a[24] ^ d4
		bc3 = t<<8 | t>>(64-8)
		a[5] = bc0 ^ (bc2 &^ bc1)
		a[16] = bc1 ^ (bc3 &^ bc2)
		a[2] = bc2 ^ (bc4 &^ bc3)
		a[13] = bc3 ^ (bc0 &^ bc4)
		a[24] = bc4 ^ (bc1 &^ bc0)

		// [Min] y = 3
		// [Min]    B[x+2y] = ROT((A[N^(i+1)(x,y)T]⊕D[x]),r[N(x,y)T]), x=0...4
		// [Min]    A[N^(i+1)(x,y)T]=B[x]⊕((NOT B[x+1]) AND B[x+2]), x=0...4
		t = a[20] ^ d0
		bc1 = t<<36 | t>>(64-36)
		t = a[6] ^ d1
		bc2 = t<<10 | t>>(64-10)
		t = a[17] ^ d2
		bc3 = t<<15 | t>>(64-15)
		t = a[3] ^ d3
		bc4 = t<<56 | t>>(64-56)
		t = a[14] ^ d4
		bc0 = t<<27 | t>>(64-27)
		a[20] = bc0 ^ (bc2 &^ bc1)
		a[6] = bc1 ^ (bc3 &^ bc2)
		a[17] = bc2 ^ (bc4 &^ bc3)
		a[3] = bc3 ^ (bc0 &^ bc4)
		a[14] = bc4 ^ (bc1 &^ bc0)

		// [Min] y = 4
		// [Min]    B[x+2y] = ROT((A[N^(i+1)(x,y)T]⊕D[x]),r[N(x,y)T]), x=0...4
		// [Min]    A[N^(i+1)(x,y)T]=B[x]⊕((NOT B[x+1]) AND B[x+2]), x=0...4
		t = a[10] ^ d0
		bc3 = t<<41 | t>>(64-41)
		t = a[21] ^ d1
		bc4 = t<<2 | t>>(64-2)
		t = a[7] ^ d2
		bc0 = t<<62 | t>>(64-62)
		t = a[18] ^ d3
		bc1 = t<<55 | t>>(64-55)
		t = a[4] ^ d4
		bc2 = t<<39 | t>>(64-39)
		a[10] = bc0 ^ (bc2 &^ bc1)
		a[21] = bc1 ^ (bc3 &^ bc2)
		a[7] = bc2 ^ (bc4 &^ bc3)
		a[18] = bc3 ^ (bc0 &^ bc4)
		a[4] = bc4 ^ (bc1 &^ bc0)

		// Round 4
		/* [Min]
		i = 3, N^i将 (x,y) 映射成 (x,7x+8y)
		C[0] = A[0,0]⊕A[0,3]⊕A[0,1]⊕A[0,4]⊕A[0,2]
		     = a[0] ^ a[15] ^ a[5] ^ a[20] ^ a[10]
		C[1] = A[1,2]⊕A[1,0]⊕A[1,3]⊕A[1,1]⊕A[1,4]
			 = a[11] ^ a[1] ^ a[16] ^ a[6] ^ a[21]
		...
		*/
		// [Min] C[x] = A[N^i(x,0)T]⊕A[N^i(x,1)T]⊕A[N^i(x,2)T]⊕A[N^i(x,3)T]⊕A[N^i(x,4)T]
		bc0 = a[0] ^ a[5] ^ a[10] ^ a[15] ^ a[20]
		bc1 = a[1] ^ a[6] ^ a[11] ^ a[16] ^ a[21]
		bc2 = a[2] ^ a[7] ^ a[12] ^ a[17] ^ a[22]
		bc3 = a[3] ^ a[8] ^ a[13] ^ a[18] ^ a[23]
		bc4 = a[4] ^ a[9] ^ a[14] ^ a[19] ^ a[24]
		// [Min] D[x] = C[x−1]⊕ROT(C[x+1],1), x = 0...4
		d0 = bc4 ^ (bc1<<1 | bc1>>63)
		d1 = bc0 ^ (bc2<<1 | bc2>>63)
		d2 = bc1 ^ (bc3<<1 | bc3>>63)
		d3 = bc2 ^ (bc4<<1 | bc4>>63)
		d4 = bc3 ^ (bc0<<1 | bc0>>63)

		// [Min] y = 0
		// [Min]    B[x+2y] = ROT((A[N^(i+1)(x,y)T]⊕D[x]),r[N(x,y)T]), x=0...4
		// [Min]    A[N^(i+1)(x,y)T]=B[x]⊕((NOT B[x+1]) AND B[x+2]), x=0...4
		// [Min] A[0,0] = A[0,0] ⊕ RC[i]
		bc0 = a[0] ^ d0
		t = a[1] ^ d1
		bc1 = t<<44 | t>>(64-44)
		t = a[2] ^ d2
		bc2 = t<<43 | t>>(64-43)
		t = a[3] ^ d3
		bc3 = t<<21 | t>>(64-21)
		t = a[4] ^ d4
		bc4 = t<<14 | t>>(64-14)
		a[0] = bc0 ^ (bc2 &^ bc1) ^ rc[i+3]
		a[1] = bc1 ^ (bc3 &^ bc2)
		a[2] = bc2 ^ (bc4 &^ bc3)
		a[3] = bc3 ^ (bc0 &^ bc4)
		a[4] = bc4 ^ (bc1 &^ bc0)

		// [Min] y = 1
		// [Min]    B[x+2y] = ROT((A[N^(i+1)(x,y)T]⊕D[x]),r[N(x,y)T]), x=0...4
		// [Min]    A[N^(i+1)(x,y)T]=B[x]⊕((NOT B[x+1]) AND B[x+2]), x=0...4
		t = a[5] ^ d0
		bc2 = t<<3 | t>>(64-3)
		t = a[6] ^ d1
		bc3 = t<<45 | t>>(64-45)
		t = a[7] ^ d2
		bc4 = t<<61 | t>>(64-61)
		t = a[8] ^ d3
		bc0 = t<<28 | t>>(64-28)
		t = a[9] ^ d4
		bc1 = t<<20 | t>>(64-20)
		a[5] = bc0 ^ (bc2 &^ bc1)
		a[6] = bc1 ^ (bc3 &^ bc2)
		a[7] = bc2 ^ (bc4 &^ bc3)
		a[8] = bc3 ^ (bc0 &^ bc4)
		a[9] = bc4 ^ (bc1 &^ bc0)

		// [Min] y = 2
		// [Min]    B[x+2y] = ROT((A[N^(i+1)(x,y)T]⊕D[x]),r[N(x,y)T]), x=0...4
		// [Min]    A[N^(i+1)(x,y)T]=B[x]⊕((NOT B[x+1]) AND B[x+2]), x=0...4
		t = a[10] ^ d0
		bc4 = t<<18 | t>>(64-18)
		t = a[11] ^ d1
		bc0 = t<<1 | t>>(64-1)
		t = a[12] ^ d2
		bc1 = t<<6 | t>>(64-6)
		t = a[13] ^ d3
		bc2 = t<<25 | t>>(64-25)
		t = a[14] ^ d4
		bc3 = t<<8 | t>>(64-8)
		a[10] = bc0 ^ (bc2 &^ bc1)
		a[11] = bc1 ^ (bc3 &^ bc2)
		a[12] = bc2 ^ (bc4 &^ bc3)
		a[13] = bc3 ^ (bc0 &^ bc4)
		a[14] = bc4 ^ (bc1 &^ bc0)

		// [Min] y = 3
		// [Min]    B[x+2y] = ROT((A[N^(i+1)(x,y)T]⊕D[x]),r[N(x,y)T]), x=0...4
		// [Min]    A[N^(i+1)(x,y)T]=B[x]⊕((NOT B[x+1]) AND B[x+2]), x=0...4
		t = a[15] ^ d0
		bc1 = t<<36 | t>>(64-36)
		t = a[16] ^ d1
		bc2 = t<<10 | t>>(64-10)
		t = a[17] ^ d2
		bc3 = t<<15 | t>>(64-15)
		t = a[18] ^ d3
		bc4 = t<<56 | t>>(64-56)
		t = a[19] ^ d4
		bc0 = t<<27 | t>>(64-27)
		a[15] = bc0 ^ (bc2 &^ bc1)
		a[16] = bc1 ^ (bc3 &^ bc2)
		a[17] = bc2 ^ (bc4 &^ bc3)
		a[18] = bc3 ^ (bc0 &^ bc4)
		a[19] = bc4 ^ (bc1 &^ bc0)

		// [Min] y = 4
		// [Min]    B[x+2y] = ROT((A[N^(i+1)(x,y)T]⊕D[x]),r[N(x,y)T]), x=0...4
		// [Min]    A[N^(i+1)(x,y)T]=B[x]⊕((NOT B[x+1]) AND B[x+2]), x=0...4
		t = a[20] ^ d0
		bc3 = t<<41 | t>>(64-41)
		t = a[21] ^ d1
		bc4 = t<<2 | t>>(64-2)
		t = a[22] ^ d2
		bc0 = t<<62 | t>>(64-62)
		t = a[23] ^ d3
		bc1 = t<<55 | t>>(64-55)
		t = a[24] ^ d4
		bc2 = t<<39 | t>>(64-39)
		a[20] = bc0 ^ (bc2 &^ bc1)
		a[21] = bc1 ^ (bc3 &^ bc2)
		a[22] = bc2 ^ (bc4 &^ bc3)
		a[23] = bc3 ^ (bc0 &^ bc4)
		a[24] = bc4 ^ (bc1 &^ bc0)
	}
}

```

# 3 Go 具体运用

```go
package main

import (
	"fmt"

	"golang.org/x/crypto/sha3"
)

func main() {
	h := sha3.New512()
	// [Min] 连续写入并即时计算当前SHA3
	h.Write([]byte{'a'})
	ha := h.Sum(nil)
	h.Write([]byte{'b'})
	hab := h.Sum(nil)
	h.Write([]byte{'c'})
	habc := h.Sum(nil)
	// [Min] 阶段性SHA3和直接计算对应数据的SHA3完全相同
	fmt.Printf("%x\n", ha)
	fmt.Printf("%x\n", sha3.Sum512([]byte{'a'}))
	fmt.Printf("%x\n", hab)
	fmt.Printf("%x\n", sha3.Sum512([]byte{'a', 'b'}))
	fmt.Printf("%x\n", habc)
	fmt.Printf("%x\n", sha3.Sum512([]byte{'a', 'b', 'c'}))

	// [Min] Sum256和ShakeSum256在相同输出长度情况下，摘要是不同的，因为他们的填充首字节不同
	s256 := sha3.Sum256([]byte{'a'})
	shake256 := make([]byte, 32)
	sha3.ShakeSum256(shake256, []byte{'a'})
	fmt.Printf("%x\n", s256)
	fmt.Printf("%x\n", shake256)
}
```

结果：

```bash
$ go run main.go
697f2d856172cb8309d6b8b97dac4de344b549d4dee61edfb4962d8698b7fa803f4f93ff24393586e28b5b957ac3d1d369420ce53332712f997bd336d09ab02a
697f2d856172cb8309d6b8b97dac4de344b549d4dee61edfb4962d8698b7fa803f4f93ff24393586e28b5b957ac3d1d369420ce53332712f997bd336d09ab02a
01c87b5e8f094d8725ed47be35430de40f6ab6bd7c6641a4ecf0d046c55cb468453796bb61724306a5fb3d90fbe3726a970e5630ae6a9cf9f30d2aa062a0175e
01c87b5e8f094d8725ed47be35430de40f6ab6bd7c6641a4ecf0d046c55cb468453796bb61724306a5fb3d90fbe3726a970e5630ae6a9cf9f30d2aa062a0175e
b751850b1a57168a5693cd924b6b096e08f621827444f70d884f5d0240d2712e10e116e9192af3c91a7ec57647e3934057340b4cf408d5a56592f8274eec53f0
b751850b1a57168a5693cd924b6b096e08f621827444f70d884f5d0240d2712e10e116e9192af3c91a7ec57647e3934057340b4cf408d5a56592f8274eec53f0
80084bf2fba02475726feb2cab2d8215eab14bc6bdd8bfb2c8151257032ecd8b
867e2cb04f5a04dcbd592501a5e8fe9ceaafca50255626ca736c138042530ba4
```
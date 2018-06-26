+++
title = "Path"
date = 2018-06-26T12:45:39+08:00
draft = false

# Tags and categories
# For example, use `tags = []` for no tags, or the form `tags = ["A Tag", "Another Tag"]` for one or more tags.
tags = ["Path"]
categories = ["Golang"]

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

# 1. Path包概要

## 1.1 概述

<!--more-->

> Package path implements utility routines for manipulating slash-separated paths.

　　`path` 包实现了对以`/`为分隔的路径的操作  
   
> The path package should only be used for paths separated by forward
> slashes, such as the paths in URLs. This package does not deal with
> Windows paths with drive letters or backslashes; to manipulate
> operating system paths, use the path/filepath package.    

　　该包只能用于对以正斜杠`/`为分隔的路径的处理，比如 URL，而不能处理带有windows中的盘符或者反斜杠`\`的路径，对于这类路径的处理需要使用 `path/filepath` 包

## 1.2 包结构

```bash
├── example_test.go
├── match.go
├── match_test.go
├── path.go
└── path_test.go
```

# 2. 深入`path`包

## 2.1 `path.go` & `path_test.go`

### 2.1.1 `Clean`

签名：`func Clean(path string) string`  

用途：`Clean`函数主要是对给定路径进行以下格式化：

- 替换多个斜杠`//`为单个斜杠`/`
- 消除`.`
- 消除`..`当且仅当前一个元素不是`..`
- 替换绝对路径开头的`/..`为`/`
- 格式化后的路径不以`/`结尾，除非该路径就是根路径`/`
- 若格式化后路径为空，则返回`.`

示例：https://play.golang.org/p/Ya85iuk0uMU

```bash
    // Already clean
	"" => "."
	"abc" => "abc"
	"abc/def" => "abc/def"
	"a/b/c" => "a/b/c"
	"." => "."
	".." => ".."
	"../.." => "../.."
	"../../abc" => "../../abc"
	"/abc" => "/abc"
	"/" => "/"

    // Remove trailing slash
	"abc/" => "abc"
	"abc/def/" => "abc/def"
	"a/b/c/" => "a/b/c"
	"./" => "."
	"../" => ".."
	"../../" => "../.."
	"/abc/" => "/abc"

    // Remove doubled slash
	"abc//def//ghi" => "abc/def/ghi"
	"//abc" => "/abc"
	"///abc" => "/abc"
	"//abc//" => "/abc"
	"abc//" => "abc"

	"abc/./def" => "abc/def"
	"/./abc/def" => "/abc/def"
	"abc/." => "abc"

    // Remove .. elements
	"abc/def/ghi/../jkl" => "abc/def/jkl"
	"abc/def/../ghi/../jkl" => "abc/jkl"
	"abc/def/.." => "abc"
	"abc/def/../.." => "."
	"/abc/def/../.." => "/"
	"abc/def/../../.." => ".."
	"/abc/def/../../.." => "/"
	"abc/def/../../../ghi/jkl/../../../mno" => "../../mno"

    // Combinations
	"abc/./../def" => "def"
	"abc//./../def" => "def"
	"abc/../../././../def" => "../../def"
```

### 2.1.2 `Split`

签名：`func Split(path string) (dir, file string)`  

用途：拆分路径为目录+文件，目录保留`/`，若路径中没有`/`，则目录为空  

示例：https://play.golang.org/p/DG8QjjWdkuq

```bash
	"a/b" => "a/" + "b"
	"a/b/" => "a/b/" + ""
	"a/" => "a/" + ""
	"a" => "" + "a"
	"/" => "/" + ""
```

### 2.1.3 `Join`

签名：`Join(elem ...string) string`

用途：把所有元素按顺序拼接为路径，并对路径格式化

示例：https://play.golang.org/p/jxcwt_fgUpt

```bash
	// zero parameters
	{[]string{} => ""},

	// one parameter
	{[]string{""} => ""},
	{[]string{"a"} => "a"},

	// two parameters
	{[]string{"a", "b"} => "a/b"},
	{[]string{"a", ""} => "a"},
	{[]string{"", "b"} => "b"},
	{[]string{"/", "a"} => "/a"},
	{[]string{"/", ""} => "/"},
	{[]string{"a/", "b"} => "a/b"},
	{[]string{"a/", ""} => "a"},
	{[]string{"", ""} => ""},
```

### 2.1.4 `Ext`

签名：`Ext(path string) string`  

用途：根据`.`返回路径中文件的扩展名，若没有`.`则返回空  

示例：https://play.golang.org/p/VxIO_oewphL

```bash
	{"path.go" => ".go"},
	{"path.pb.go" => ".go"},
	{"a.dir/b" => ""},
	{"a.dir/b.go" => ".go"},
	{"a.dir/" => ""},
```

### 2.1.5 `Base`

签名：`Base(path string) string`  

用途：先清除路径末尾的`/`（如果有的话），再根据最后一个`/`，返回该元素，若没有`/`，则返回`.`  

示例：https://play.golang.org/p/bW-KYszq1fE

```bash
	{"" => "."},
	{"." => "."},
	{"/." => "."},
	{"/" => "/"},
	{"////" => "/"},
	{"x/" => "x"},
	{"abc" => "abc"},
	{"abc/def" => "def"},
	{"a/b/.x" => ".x"},
	{"a/b/c." => "c."},
	{"a/b/c.x" => "c.x"},
```

### 2.1.6 `IsAbs`

签名：`IsAbs(path string) bool`  

用途：判断路径是否为绝对路径，即以`/`开头  

示例：https://play.golang.org/p/MWv0m9Q8I-J

```bash
	{"" => false},
	{"/" => true},
	{"/usr/bin/gcc" => true},
	{".." => false},
	{"/a/../bb" => true},
	{"." => false},
	{"./" => false},
	{"lala" => false},
```

### 2.1.7 `Dir`

签名：`Dir(path string) string`  

用途：返回去除最后一项后的目录路径,并格式化  

示例：https://play.golang.org/p/DBULKf343C6

```bash
	{"" => "."},
	{"." => "."},
	{"/." => "/"},
	{"/" => "/"},
	{"////" => "/"},
	{"/foo" => "/"},
	{"x/" => "x"},
	{"abc" => "."},
	{"abc/def" => "abc"},
	{"abc////def" => "abc"},
	{"a/b/.x" => "a/b"},
	{"a/b/c." => "a/b"},
	{"a/b/c.x" => "a/b"},
```

## 2.2 `match.go` & `match_test.go`

### 2.2.1 `Match`

签名：`func Match(pattern, name string) (matched bool, err error)`  

用途：根据给定的模式对路径进行匹配，模式如下：

```bash
	pattern:
		{ term }
	term:
		'*'         matches any sequence of non-/ characters 匹配任意数量的所有非/字符
		'?'         matches any single non-/ character 匹配所有单个非/字符
		'[' [ '^' ] { character-range } ']' 区间匹配，^表示除了该区间，匹配不能为空，至少需要一个
		            character class (must be non-empty)
		c           matches character c (c != '*', '?', '\\', '[') 匹配单个确定字符，除'*', '?', '\\', '['
		'\\' c      matches character c 可以看作转义匹配'*', '?', '\\', '['

	character-range:
		c           matches character c (c != '\\', '-', ']') 在区间匹配中匹配单个确定字符，除'\\', '-', ']'
		'\\' c      matches character c 可以看作在区间匹配中转义匹配'\\', '-', ']'
		lo '-' hi   matches character c for lo <= c <= hi 区间范围
```

示例：https://play.golang.org/p/yhfME8jBmn1

```go
	{"abc", "abc", true, nil},
	{"*", "abc", true, nil},
	{"*c", "abc", true, nil},
	{"a*", "a", true, nil},
	{"a*", "abc", true, nil},
	{"a*", "ab/c", false, nil},
	{"a*/b", "abc/b", true, nil},
	{"a*/b", "a/c/b", false, nil},
	{"a*b*c*d*e*/f", "axbxcxdxe/f", true, nil},
	{"a*b*c*d*e*/f", "axbxcxdxexxx/f", true, nil},
	{"a*b*c*d*e*/f", "axbxcxdxe/xxx/f", false, nil},
	{"a*b*c*d*e*/f", "axbxcxdxexxx/fff", false, nil},
	{"a*b?c*x", "abxbbxdbxebxczzx", true, nil},
	{"a*b?c*x", "abxbbxdbxebxczzy", false, nil},
	{"ab[c]", "abc", true, nil},
	{"ab[b-d]", "abc", true, nil},
	{"ab[e-g]", "abc", false, nil},
	{"ab[^c]", "abc", false, nil},
	{"ab[^b-d]", "abc", false, nil},
	{"ab[^e-g]", "abc", true, nil},
	{"a\\*b", "a*b", true, nil},
	{"a\\*b", "ab", false, nil},
	{"a?b", "a☺b", true, nil},
	{"a[^a]b", "a☺b", true, nil},
	{"a???b", "a☺b", false, nil},
	{"a[^a][^a][^a]b", "a☺b", false, nil},
	{"[a-ζ]*", "α", true, nil},
	{"*[a-ζ]", "A", false, nil},
	{"a?b", "a/b", false, nil},
	{"a*b", "a/b", false, nil},
	{"[\\]a]", "]", true, nil},
	{"[\\-]", "-", true, nil},
	{"[x\\-]", "x", true, nil},
	{"[x\\-]", "-", true, nil},
	{"[x\\-]", "z", false, nil},
	{"[\\-x]", "x", true, nil},
	{"[\\-x]", "-", true, nil},
	{"[\\-x]", "a", false, nil},
	{"[]a]", "]", false, ErrBadPattern},
	{"[-]", "-", false, ErrBadPattern},
	{"[x-]", "x", false, ErrBadPattern},
	{"[x-]", "-", false, ErrBadPattern},
	{"[x-]", "z", false, ErrBadPattern},
	{"[-x]", "x", false, ErrBadPattern},
	{"[-x]", "-", false, ErrBadPattern},
	{"[-x]", "a", false, ErrBadPattern},
	{"\\", "a", false, ErrBadPattern},
	{"[a-b-c]", "a", false, ErrBadPattern},
	{"[", "a", false, ErrBadPattern},
	{"[^", "a", false, ErrBadPattern},
	{"[^bc", "a", false, ErrBadPattern},
	{"a[", "a", false, nil},
	{"a[", "ab", false, ErrBadPattern},
	{"*x", "xxx", true, nil},
```
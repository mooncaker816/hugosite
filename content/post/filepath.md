+++
title = "Filepath"
date = 2018-06-26T15:39:18+08:00
draft = false

# Tags and categories
# For example, use `tags = []` for no tags, or the form `tags = ["A Tag", "Another Tag"]` for one or more tags.
tags = ["Filepath"]
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

# 1. Filepath包概要

## 1.1 概述

<!--more-->

> Package filepath implements utility routines for manipulating filename paths
> in a way compatible with the target operating system-defined file paths.

　　`filepath`包实现了对不同操作系统的文件路径的统一操作

> The filepath package uses either forward slashes or backslashes,
> depending on the operating system. To process paths such as URLs
> that always use forward slashes regardless of the operating
> system, see the path package.

　　根据不同的操作系统，该包既可以处理以正斜杠`/`为分隔的路径，也可以处理以反斜杠`\`为分隔的路径。对于 URL 的处理，总是使用正斜杠`/`，无关操作系统。

<!--more-->

## 1.2 包结构

```bash
├── example_test.go
├── example_unix_test.go
├── export_test.go
├── export_windows_test.go
├── match.go
├── match_test.go
├── path.go
├── path_plan9.go
├── path_test.go
├── path_unix.go
├── path_windows.go
├── path_windows_test.go
├── symlink.go
├── symlink_unix.go
└── symlink_windows.go
```

# 2. 深入`filepath`包

## 2.1 `path.go` & `path_test.go`

### 2.1.1 `Clean`

签名：`func Clean(path string) string`  

用途：对路径进行格式化，与`path.Clean`基本一致，windows 系统的根目录为`C:\`

示例：<https://play.golang.org/p/UZqq84JBFet>  

```go
	// Already clean
	{"abc" => "abc"},
	{"abc/def" => "abc/def"},
	{"a/b/c" => "a/b/c"},
	{"." => "."},
	{".." => ".."},
	{"../.." => "../.."},
	{"../../abc" => "../../abc"},
	{"/abc" => "/abc"},
	{"/" => "/"},

	// Empty is current dir
	{"" => "."},

	// Remove trailing slash
	{"abc/" => "abc"},
	{"abc/def/" => "abc/def"},
	{"a/b/c/" => "a/b/c"},
	{"./" => "."},
	{"../" => ".."},
	{"../../" => "../.."},
	{"/abc/" => "/abc"},

	// Remove doubled slash
	{"abc//def//ghi" => "abc/def/ghi"},
	{"//abc" => "/abc"},
	{"///abc" => "/abc"},
	{"//abc//" => "/abc"},
	{"abc//" => "abc"},

	// Remove . elements
	{"abc/./def" => "abc/def"},
	{"/./abc/def" => "/abc/def"},
	{"abc/." => "abc"},

	// Remove .. elements
	{"abc/def/ghi/../jkl" => "abc/def/jkl"},
	{"abc/def/../ghi/../jkl" => "abc/jkl"},
	{"abc/def/.." => "abc"},
	{"abc/def/../.." => "."},
	{"/abc/def/../.." => "/"},
	{"abc/def/../../.." => ".."},
	{"/abc/def/../../.." => "/"},
	{"abc/def/../../../ghi/jkl/../../../mno" => "../../mno"},
	{"/../abc" => "/abc"},

	// Combinations
	{"abc/./../def" => "def"},
	{"abc//./../def" => "def"},
	{"abc/../../././../def" => "../../def"},

	{`c:` => `c:.`},
	{`c:\` => `c:\`},
	{`c:\abc` => `c:\abc`},
	{`c:abc\..\..\.\.\..\def` => `c:..\..\def`},
	{`c:\abc\def\..\..` => `c:\`},
	{`c:\..\abc` => `c:\abc`},
	{`c:..\abc` => `c:..\abc`},
	{`\` => `\`},
	{`/` => `\`},
	{`\\i\..\c$` => `\c$`},
	{`\\i\..\i\c$` => `\i\c$`},
	{`\\i\..\I\c$` => `\I\c$`},
	{`\\host\share\foo\..\bar` => `\\host\share\bar`},
	{`//host/share/foo/../baz` => `\\host\share\baz`},
	{`\\a\b\..\c` => `\\a\b\c`},
	{`\\a\b` => `\\a\b`},
```

### 2.1.2 `ToSlash` & `FromSlash`

签名：`func ToSlash(path string) string` & `func FromSlash(path string) string`  

用途：将路径中的分隔符替换为`/` & 将路径中的`/`分隔符替换为系统对应的分隔符

示例：<https://play.golang.org/p/FB-HZSqbuSd>

```go
	{"", ""},
	{"/", string(sep)},
	{"/a/b", string([]byte{sep, 'a', sep, 'b'})},
	{"a//b", string([]byte{'a', sep, sep, 'b'})},
```

### 2.1.3 `SplitList`

签名：`func SplitList(path string) []string`  

用途：根据系统的 List分隔符（如环境变量`PATH`中包含的多个路径之间的`:` `;`）,将List路径拆分成单个路径组成的 slice，若List路径为空，则返回空 slice  

示例：<https://play.golang.org/p/bQOhCR4kvFq>

```go
	{"", []string{}},
	{string([]byte{'a', lsep, 'b'}), []string{"a", "b"}},
	{string([]byte{lsep, 'a', lsep, 'b'}), []string{"", "a", "b"}},
    
	// quoted
	{`"a"`, []string{`a`}},

	// semicolon
	{`";"`, []string{`;`}},
	{`"a;b"`, []string{`a;b`}},
	{`";";`, []string{`;`, ``}},
	{`;";"`, []string{``, `;`}},

	// partially quoted
	{`a";"b`, []string{`a;b`}},
	{`a; ""b`, []string{`a`, ` b`}},
	{`"a;b`, []string{`a;b`}},
	{`""a;b`, []string{`a`, `b`}},
	{`"""a;b`, []string{`a;b`}},
	{`""""a;b`, []string{`a`, `b`}},
	{`a";b`, []string{`a;b`}},
	{`a;b";c`, []string{`a`, `b;c`}},
	{`"a";b";c`, []string{`a`, `b;c`}},
```

### 2.1.4 `Split`

签名：`func Split(path string) (dir, file string)`  

用途：拆分路径为目录+文件名  

示例：<https://play.golang.org/p/ABl-Ph464rW>

```go
	{"a/b", "a/", "b"},
	{"a/b/", "a/b/", ""},
	{"a/", "a/", ""},
	{"a", "", "a"},
	{"/", "/", ""},

	{`c:`, `c:`, ``},
	{`c:/`, `c:/`, ``},
	{`c:/foo`, `c:/`, `foo`},
	{`c:/foo/bar`, `c:/foo/`, `bar`},
	{`//host/share`, `//host/share`, ``},
	{`//host/share/`, `//host/share/`, ``},
	{`//host/share/foo`, `//host/share/`, `foo`},
	{`\\host\share`, `\\host\share`, ``},
	{`\\host\share\`, `\\host\share\`, ``},
	{`\\host\share\foo`, `\\host\share\`, `foo`},
```

### 2.1.5 `Join`

签名：`func Join(elem ...string) string`  

用途：拼接路径  

示例：<https://play.golang.org/p/RRhT3gH_SCJ>

```go
	// zero parameters
	{[]string{}, ""},

	// one parameter
	{[]string{""}, ""},
	{[]string{"/"}, "/"},
	{[]string{"a"}, "a"},

	// two parameters
	{[]string{"a", "b"}, "a/b"},
	{[]string{"a", ""}, "a"},
	{[]string{"", "b"}, "b"},
	{[]string{"/", "a"}, "/a"},
	{[]string{"/", "a/b"}, "/a/b"},
	{[]string{"/", ""}, "/"},
	{[]string{"//", "a"}, "/a"},
	{[]string{"/a", "b"}, "/a/b"},
	{[]string{"a/", "b"}, "a/b"},
	{[]string{"a/", ""}, "a"},
	{[]string{"", ""}, ""},

	// three parameters
	{[]string{"/", "a", "b"}, "/a/b"},

	{[]string{`directory`, `file`}, `directory\file`},
	{[]string{`C:\Windows\`, `System32`}, `C:\Windows\System32`},
	{[]string{`C:\Windows\`, ``}, `C:\Windows`},
	{[]string{`C:\`, `Windows`}, `C:\Windows`},
	{[]string{`C:`, `a`}, `C:a`},
	{[]string{`C:`, `a\b`}, `C:a\b`},
	{[]string{`C:`, `a`, `b`}, `C:a\b`},
	{[]string{`C:.`, `a`}, `C:a`},
	{[]string{`C:a`, `b`}, `C:a\b`},
	{[]string{`C:a`, `b`, `d`}, `C:a\b\d`},
	{[]string{`\\host\share`, `foo`}, `\\host\share\foo`},
	{[]string{`\\host\share\foo`}, `\\host\share\foo`},
	{[]string{`//host/share`, `foo/bar`}, `\\host\share\foo\bar`},
	{[]string{`\`}, `\`},
	{[]string{`\`, ``}, `\`},
	{[]string{`\`, `a`}, `\a`},
	{[]string{`\\`, `a`}, `\a`},
	{[]string{`\`, `a`, `b`}, `\a\b`},
	{[]string{`\\`, `a`, `b`}, `\a\b`},
	{[]string{`\`, `\\a\b`, `c`}, `\a\b\c`},
	{[]string{`\\a`, `b`, `c`}, `\a\b\c`},
	{[]string{`\\a\`, `b`, `c`}, `\a\b\c`},
```

### 2.1.6 `Ext`

签名：`func Ext(path string) string`  

用途：根据最后一个元素中的最后一个`.`，返回路径中文件的扩展名，若没有`.`，返回空  

示例：<https://play.golang.org/p/K5TZl6W-ByS>

```go
	{"path.go", ".go"},
	{"path.pb.go", ".go"},
	{"a.dir/b", ""},
	{"a.dir/b.go", ".go"},
	{"a.dir/", ""},
```

### 2.1.7 `EvalSymlinks`

签名：`func EvalSymlinks(path string) (string, error)`  

用途：对symlink文件解引用，并对结果路径格式化  

示例：<https://play.golang.org/p/3RwUZ9tfHos> (run local)

### 2.1.8 `Abs`

签名：`func Abs(path string) (string, error)`  

用途：返回绝对路径并格式化，如果给定的路径不是绝对路径，则会加上当前目录形成绝对路径  

示例：<https://play.golang.org/p/UMr9_z4AsWR>

### 2.1.9 `Rel`

签名：`func Rel(basepath, targpath string) (string, error)`  

用途：根据 basepath 将 targpath 以相对路径的方式返回，并格式化  

示例：<https://play.golang.org/p/KFoNtsbW68D>

```go
	{"a/b", "a/b", "."},
	{"a/b/.", "a/b", "."},
	{"a/b", "a/b/.", "."},
	{"./a/b", "a/b", "."},
	{"a/b", "./a/b", "."},
	{"ab/cd", "ab/cde", "../cde"},
	{"ab/cd", "ab/c", "../c"},
	{"a/b", "a/b/c/d", "c/d"},
	{"a/b", "a/b/../c", "../c"},
	{"a/b/../c", "a/b", "../b"},
	{"a/b/c", "a/c/d", "../../c/d"},
	{"a/b", "c/d", "../../c/d"},
	{"a/b/c/d", "a/b", "../.."},
	{"a/b/c/d", "a/b/", "../.."},
	{"a/b/c/d/", "a/b", "../.."},
	{"a/b/c/d/", "a/b/", "../.."},
	{"../../a/b", "../../a/b/c/d", "c/d"},
	{"/a/b", "/a/b", "."},
	{"/a/b/.", "/a/b", "."},
	{"/a/b", "/a/b/.", "."},
	{"/ab/cd", "/ab/cde", "../cde"},
	{"/ab/cd", "/ab/c", "../c"},
	{"/a/b", "/a/b/c/d", "c/d"},
	{"/a/b", "/a/b/../c", "../c"},
	{"/a/b/../c", "/a/b", "../b"},
	{"/a/b/c", "/a/c/d", "../../c/d"},
	{"/a/b", "/c/d", "../../c/d"},
	{"/a/b/c/d", "/a/b", "../.."},
	{"/a/b/c/d", "/a/b/", "../.."},
	{"/a/b/c/d/", "/a/b", "../.."},
	{"/a/b/c/d/", "/a/b/", "../.."},
	{"/../../a/b", "/../../a/b/c/d", "c/d"},
	{".", "a/b", "a/b"},
	{".", "..", ".."},

	// can't do purely lexically
	{"..", ".", "err"},
	{"..", "a", "err"},
	{"../..", "..", "err"},
	{"a", "/a", "err"},
	{"/a", "a", "err"},

	{`C:a\b\c`, `C:a/b/d`, `..\d`},
	{`C:\`, `D:\`, `err`},
	{`C:`, `D:`, `err`},
	{`C:\Projects`, `c:\projects\src`, `src`},
	{`C:\Projects`, `c:\projects`, `.`},
	{`C:\Projects\a\..`, `c:\projects`, `.`},
```

### 2.1.10 `Walk`

签名：`func Walk(root string, walkFn WalkFunc) error`  

用途：用于遍历目录树  

示例：<https://play.golang.org/p/1fYRtezNBX->

`type WalkFunc func(path string, info os.FileInfo, err error) error`
`WalkFunc` 函数一般是一个闭包，用于处理目录树中的每个文件/目录，如：

```go
	errors := make([]error, 0, 10)
	clear := true
	markFn := func(path string, info os.FileInfo, err error) error {
		return mark(info, err, &errors, clear)
	}
	// Expect no errors.
	err := filepath.Walk(tree.name, markFn)
```

### 2.1.11 `Base`

签名：`func Base(path string) string`  

用途：返回最后一个元素，如果路径为空，则返回`.`，如果路径全是分隔符，则返回单个分隔符

示例：<https://play.golang.org/p/0F6PSQjwOTX>

```go
	{"", "."},
	{".", "."},
	{"/.", "."},
	{"/", "/"},
	{"////", "/"},
	{"x/", "x"},
	{"abc", "abc"},
	{"abc/def", "def"},
	{"a/b/.x", ".x"},
	{"a/b/c.", "c."},
	{"a/b/c.x", "c.x"},

	{`c:\`, `\`},
	{`c:.`, `.`},
	{`c:\a\b`, `b`},
	{`c:a\b`, `b`},
	{`c:a\b\c`, `c`},
	{`\\host\share\`, `\`},
	{`\\host\share\a`, `a`},
	{`\\host\share\a\b`, `b`},
```

### 2.1.12 `Dir`

签名：`func Dir(path string) string`  

用途：返回除去最后一个元素的路径，并格式化。如果路径为空，返回.，如果路径全是分隔符，返回单个分隔符，返回的路径不以分隔符结尾，除非该路径为根目录  

示例：<https://play.golang.org/p/-6CrUtV9_CO>

```go
	{"", "."},
	{".", "."},
	{"/.", "/"},
	{"/", "/"},
	{"////", "/"},
	{"/foo", "/"},
	{"x/", "x"},
	{"abc", "."},
	{"abc/def", "abc"},
	{"a/b/.x", "a/b"},
	{"a/b/c.", "a/b"},
	{"a/b/c.x", "a/b"},

	{`c:\`, `c:\`},
	{`c:.`, `c:.`},
	{`c:\a\b`, `c:\a`},
	{`c:a\b`, `c:a`},
	{`c:a\b\c`, `c:a\b`},
	{`\\host\share`, `\\host\share`},
	{`\\host\share\`, `\\host\share\`},
	{`\\host\share\a`, `\\host\share\`},
	{`\\host\share\a\b`, `\\host\share\a`},
```

### 2.1.13 `VolumeName`

签名：`func VolumeName(path string) string`  

用途：Windows系统返回卷名，其他系统返回空

示例：https://play.golang.org/p/uxvpRgAy9Lg

```go
    	{`c:/foo/bar`, `c:`},
    	{`c:`, `c:`},
    	{`2:`, ``},
    	{``, ``},
    	{`\\\host`, ``},
    	{`\\\host\`, ``},
    	{`\\\host\share`, ``},
    	{`\\\host\\share`, ``},
    	{`\\host`, ``},
    	{`//host`, ``},
        {`\\host\`, ``},
        {`//host/`, ``},
        {`\\host\share`, `\\host\share`},
        {`//host/share`, `//host/share`},
        {`\\host\share\`, `\\host\share`},
        {`//host/share/`, `//host/share`},
        {`\\host\share\foo`, `\\host\share`},
        {`//host/share/foo`, `//host/share`},
        {`\\host\share\\foo\\\bar\\\\baz`, `\\host\share`},
        {`//host/share//foo///bar////baz`, `//host/share`},
        {`\\host\share\foo\..\bar`, `\\host\share`},
        {`//host/share/foo/../bar`, `//host/share`},
```

### 2.1.14 `IsAbs`

签名：`func IsAbs(path string) bool`

用途：判断是否为绝对路径，在 Unix 中，以`/`开始；在 Windows 中以某个盘符开始  

示例：https://play.golang.org/p/JV2dVvYUaYP

```go
	{"", false},
	{"/", true},
	{"/usr/bin/gcc", true},
	{"..", false},
	{"/a/../bb", true},
	{".", false},
	{"./", false},
	{"lala", false},
```

## 2.2 `match.go` & `match_test.go`

### 2.2.1 `Match`

签名：`func Match(pattern, name string) (matched bool, err error)`

用途：同`path.Match`

示例：https://play.golang.org/p/N5knl-o3yWM

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

### 2.2.2 `Glob`

签名：`func Glob(pattern string) (matches []string, err error)`

用途：列出与指定的模式 pattern 完全匹配的文件或目录（匹配原则同`Match`）  

示例：https://play.golang.org/p/GxqJkYQp_xm (run local)


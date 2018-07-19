+++
title = "Sort"
date = 2018-06-27T14:21:20+08:00
draft = false

# Tags and categories
# For example, use `tags = []` for no tags, or the form `tags = ["A Tag", "Another Tag"]` for one or more tags.
tags = ["Sort"]
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

# 1. Sort包概要

## 1.1 概述

<!--more-->

　　该包实现了四种基本排序算法：插入排序、快速排序、堆排序和归并排序，它们只被`Sort`函数内部调用，程序会根据数据的规模来择优选择排序方法。使用者只需要确保排序对象实现了`sort.Interface`定义的三个方法：获取数据集合长度的`Len()`方法、比较两个元素大小的`Less()`方法和交换两个元素位置的`Swap()`方法，就可以顺利对数据集合进行排序。  

## 1.2 包结构

```bash
├── example_interface_test.go
├── example_keys_test.go
├── example_multi_test.go
├── example_search_test.go
├── example_test.go
├── example_wrapper_test.go
├── export_test.go
├── genzfunc.go 用于生成zfuncversion.go供 sort.Slice 使用
├── search.go 对已排序序列进行二分查找
├── search_test.go
├── slice.go 对一般数据集进行排序
├── sort.go 常用排序
├── sort_test.go
└── zfuncversion.go 由genzfunc.go根据 sort.go 生成
```

# 2. 深入`sort`包

## 2.1 `sort.go` & `sort_test.go`

### 2.1.1 `Sort`

签名：`func Sort(data Interface)`

用途：对实现了`Interface`接口的数据集进行排序  

### 2.1.2 `Reverse`

签名：`func Reverse(data Interface) Interface`

用途：可以允许将数据按原有Less()定义的排序方式逆序排序，而不必修改Less()代码  

示例：

```go
func ExampleReverse() {
	s := []int{5, 2, 6, 3, 1, 4} // unsorted
	sort.Sort(sort.Reverse(sort.IntSlice(s)))
	fmt.Println(s)
	// Output: [6 5 4 3 2 1]
}
```

### 2.1.3 `IsSorted`

签名：`func IsSorted(data Interface) bool`

用途：判断数据是否已经按 Less 方法排序

示例：

```go
func ExampleIsSorted() {
	s := []int{1, 2, 3, 4, 5, 6} // sorted ascending
	fmt.Println(sort.IsSorted(sort.IntSlice(s)))

	s = []int{6, 5, 4, 3, 2, 1} // sorted descending
	fmt.Println(sort.IsSorted(sort.IntSlice(s)))

	s = []int{3, 2, 4, 1, 5} // unsorted
	fmt.Println(sort.IsSorted(sort.IntSlice(s)))

	// Output: true
	// false
	// false
}
```

### 2.1.4
+++
title = "Go并发模式1"
date = 2018-06-13T15:02:12+08:00
draft = false

# Tags and categories
# For example, use `tags = []` for no tags, or the form `tags = ["A Tag", "Another Tag"]` for one or more tags.
tags = ["Go patterns"]
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
# Or-Channel

<!--more-->

- 使用场景：  
    当你需要同时监测多个信号时，只要接收到其中任一个信号，就认为信号接收成功，需要进行下一步处理

- 代码：

    ```go
    func or(channels ...<-chan interface{}) <-chan interface{} {
        switch len(channels) {
        case 0:
            return nil
        case 1:
            return channels[0]
        }
        orDone := make(chan interface{})
        go func() {
            defer close(orDone)
            switch len(channels) {
            case 2:
                select {
                case <-channels[0]:
                case <-channels[1]:
                }
            default:
                select {
                case <-channels[0]:
                case <-channels[1]:
                case <-channels[2]:
                case <-or(append(channels[3:], orDone)...):
                }
            }
        }()
        return orDone
    }
    ```

- 测试：

    ```go
    func TestOr(t *testing.T) {
        st := time.Now()
        r := rand.New(rand.NewSource(time.Now().Unix()))
        <-or(
            randSig(r),
            randSig(r),
            randSig(r),
            randSig(r),
            randSig(r),
        )
        fmt.Printf("closed after %v!\n", time.Since(st))
    }

    func randSig(r *rand.Rand) <-chan interface{} {
        ch := make(chan interface{})
        go func() {
            defer close(ch)
            sec := time.Duration(r.Int63n(10)+3) * time.Second
            fmt.Printf("closing after %v!\n", sec)
            time.Sleep(sec)
        }()
        return ch
    }
    ```
    结果：

    ```bash
    closing after 4s!
    closing after 10s!
    closing after 3s!
    closing after 9s!
    closing after 11s!
    closed after 3.001062582s!
    ```
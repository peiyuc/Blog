---
title: 线程中断和关闭
date: 
tags:
---

------
本文是java并发编程实战第7章的读书笔记，以及对文章中的部分内容做一些补充和解释.
> Java没有提供任何机制来安全的终止线程，但它提供了中断（Interruption），这是一种协作机制，能够使一个线程终止另一个线程的当前工作。

为何要做成协作式的？因为如果立即停止某个线程或任务，会使共享数据结构处于不一致的状态；如果使用协作式的方式：当需要停止时，首先完成当前的工作再停止，这样灵活性更高。

我们可以通过设置一个“已请求取消（cancellation Requested）”标志，同时让任务定时去检验这个标志的值，如果设置了该标志，则取消该任务。但是这种方式会有个一个问题，如果任务中的某一个步骤是阻塞的，那么该人物就会永远无法取消。如何解决这个问题？

java提供了中断线程以及查询线程中断状态的方法，代码如下所示：
```
public class Thread {
    // Interrupts this thread.
    public void interrupt() {...}

    // Tests whether this thread has been interrupted. 
    // The interrupted status of the thread is unaffected by this method.
    public boolean isInterrupted() {...}

    // Tests whether the current thread has been interrupted.
    // The interrupted status of the thread is cleared by this method.
    public static boolean interrupted() {...}
}
```
这三个方法的作用注释写的很明白，第二和第三个方法的区别就是一个不会影响中断状态，一个会。
阻塞库的方法，如Thread.sleep()和Object.wait()都会检查线程的中断状态，并在发现中断时提前返回。同时会执行下面两个动作：
* 清除中断状态
* 抛出InterruptedException异常

> 调用interrupt并不意味着立即停止目标线程正在进行的工作，而只是传递了请求中断的消息

换句话说就是，调用interrupt方法之后，线程并不会立即退出，而是会等某个校验线程中断标志的动作，如果没有则线程并不会退出执行。而对某些可以相应中断的方法wait、sleep和join等，将会严格处理这种请求，清除中断状态并抛出InterruptedException异常。

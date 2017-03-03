---
title: 线程中断和关闭
date: 
tags:
---

------
本文是java并发编程实战第7章的读书笔记，以及对文章中的部分内容做一些补充和解释.
> Java没有提供任何机制来安全的终止线程，但它提供了中断（Interruption），这是一种协作机制，能够使一个线程终止另一个线程的当前工作。

为何要做成协作式的？

因为如果立即停止某个线程或任务，会使共享数据结构处于不一致的状态；如果使用协作式的方式：当需要停止时，首先完成当前的工作再停止，这样灵活性更高。

如何实现线程的中断？

我们可以通过设置一个“已请求取消（cancellation Requested）”标志，同时让任务定时去检验这个标志的值，如果设置了该标志，则取消该任务。但是这种方式会有个一个问题，如果任务中的某一个步骤是阻塞的，那么该任务就会永远无法取消。

如何解决上面的问题？

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
如果捕获到可中断的阻塞方法抛出的InterruptedException或检测到中断后，应该如何处理，有以下两个原则：

* 如果遇到的是可中断的阻塞方法抛出InterruptedException，可以继续向方法调用栈的上层抛出该异常；如果是检测到中断，则可清除中断状态并抛出InterruptedException，使当前方法也成为一个可中断的方法。
* 若有时候不太方便在方法上抛出InterruptedException，比如要实现的某个接口中的方法签名上没有throws InterruptedException，这时就可以捕获可中断方法的InterruptedException并通过Thread.currentThread.interrupt()来重新设置中断状态。如果是检测并清除了中断状态，亦是如此。

我们还可以使用Feature实现取消。

### 停止基于线程的服务
##### 如何去取消一个生产者消费者任务？
取消任务时，要让消费者把消费队列中的任务执行完成，且在发出中断指令之后，生产者线程无法再往任务队列里新增任务。

##### ExecuteService的关闭方式

* shutdown()
可以达到取消线程服务的要求，在执行玩工作队列里的任务之后采取关闭线程池

* shutdownNow()
会尝试取消正在执行的任务，同时返回所有已提交但是尚未执行的任务。但是我们无法得知哪些任务已经在执行但未执行完毕，书中通过在中断之后写入取消队列的方式，保证任务不会丢失

### 处理非正常的线程终止-UncaughtExceptionHandler
单线程可以通过try...catch捕获异常，而在多线程情况下则无法捕获，可以在任务内部捕获并在finally里处理异常。但是java提供了一个UncaughtExceptionHandler接口用来做类似的事。它可以检测出由于某个未捕获的异常而终结的情况。
相关信息可以参考文章二。

### 参考
* [详细分析Java中断机制](http://www.infoq.com/cn/articles/java-interrupt-mechanism)
* [JAVA多线程之UncaughtExceptionHandler——处理非正常的线程中止](http://www.importnew.com/18619.html)

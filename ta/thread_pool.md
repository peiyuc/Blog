---
title: TheadPoolExecutor线程池
date: 
tags:
---

ThreadPoolExecutor线程池创建方法有两种：
* Executors提供了常用线程池的工厂方法；
* 通过ThreadPoolExecutor构造方法创建

一般使用Executors提供的默认线程池，当默认的执行策略不满足需求，那么可以通过ThreadPoolExecutor的构造函数来实例化一个对象，并根据自己的需求来定制，下面是ThreadPoolExecutor通用的构造函数：

```
public ThreadPoolExecutor(int corePoolSize,
                              int maximumPoolSize,
                              long keepAliveTime,
                              TimeUnit unit,
                              BlockingQueue<Runnable> workQueue
                              ThreadFactory threadFactory,
                              RejectedExecutionHandler handler) {
        ...
}
```

* corePoolSize

线程池的基本大小，也就是线程池的目标大小，即在没有任务执行时线程池的大小；在工作队列满的情况下会创建超出这个数量的线程；

* maximumPoolSize

可同时活动的线程数量的上限，在工作队列满时创建超出corePoolSize的线程数量；

* keepAliveTime

存活时间，如果某个线程的空闲时间超过存活时间，那么将被标记为可回收的，并在当前线程池的线程超过了corePoolSize时，这个线程将被终止；

* workQueue

工作队列，分为无界队列、有界队列和同步移交，用户存放待执行的任务；
只有当任务是相互独立时，为线程池或工作队列设置界限才是合理的。如果任务之间存在依赖，那么有界线程池或队列就可能导致线程“饥饿”死锁的问题。此时应该使用无界线程池。

* RejectedExecutionHandler：饱和策略

JDK文档清楚的说明了什么情况下回执行饱和策略

> If we cannot queue task, then we try to add a new thread.  If it fails, we know we are shut down or saturated and so reject the task.

当工作队列已满，就尝试增加一个线程，如果失败就表示线程池已关闭或已饱和，那么将拒绝该任务

* ThreadFactory：线程工厂

每当线程池需要创建一个新的线程时，都是通过线程的工厂方法（如下）去创建。
```
public interface ThreadFactory {
    Thread newThread(Runnable r);
}
```
默认的线程工厂方法将创建一个新的、非守护的线程，并且不包含特殊的配置信息，如下：
```
 static class DefaultThreadFactory implements ThreadFactory {
         private static final AtomicInteger poolNumber = new AtomicInteger(1);
         private final ThreadGroup group;
         private final AtomicInteger threadNumber = new AtomicInteger(1);
         private final String namePrefix;
 
         DefaultThreadFactory() {
             SecurityManager s = System.getSecurityManager();
             group = (s != null) ? s.getThreadGroup() :
                                   Thread.currentThread().getThreadGroup();
             namePrefix = "pool-" +
                           poolNumber.getAndIncrement() +
                          "-thread-";
         }
 
         public Thread newThread(Runnable r) {
             Thread t = new Thread(group, r,
                                   namePrefix + threadNumber.getAndIncrement(),
                                   0);
             if (t.isDaemon())
                 t.setDaemon(false);
             if (t.getPriority() != Thread.NORM_PRIORITY)
                 t.setPriority(Thread.NORM_PRIORITY);
             return t;
         }
}
```

一般我们需要一个特定的线程池的名字，从而可以在错误日志信息中区分来自不同线程池的线程，就需要自己实现ThreadFactory接口，定制newThread方法。

* 定制ThreadPoolExecutor

通过ThreadPoolExecutor构造函数创建线程池后，仍然可以通过各种setter方法来修改大多数构造参数；如果线程池是通过Executors中的某个工厂方法提供的，那么可以通过强制类型转换为ThreadPoolExecutor以访问设置器。为避免给这种情况的发生，Executors提供了unconfigurableExecutorService方法。该方法对一个现有的ExecutorService方法进行包装，使其只暴露出ExecutorService方法，因此不能进行各种参数的配置，防止不信任代码对线程池进行修改。

* 扩展ThreadPoolExecutor

ThreadPoolExecutor是可以扩展的，子类可以重写beforeExecute、afterExecute和teminated方法。这些方法可以日志、计时、监视或统计信息收集的功能。任务无论是从run中正常返回还是抛出一个异常而返回，都会调用afterExecute方法。如果beforeExecute方法抛出一个RuntimeExeception，那么任务将不会执行，并且afterExecute方法也得不到调用。在线程池完成关闭操作时将调用terminate方法，也就是所有任务都已经完成并且所有工作者也已经关闭后。
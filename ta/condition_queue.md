---
title: java并发系列之条件队列
date: 2017-03-01 14:15:41
tags:
---

------
### 什么是条件队列？

{% blockquote %}
A condition queue gets its name because it gives a group of threads-called the wait set-a way to wait for a specific condition to become true. Unlike typical queues in which the elements are data items, the elements of condition queue are the threads waiting for condition.
{% endblockquote %}

这是[java并发编程实战](https://book.douban.com/subject/10484692/)里的解释，wait set是什么？感觉没怎么说清楚。另一种解释是说条件队列可以协同不同线程之间的工作（太抽象）。条件队列的定义暂且放下，先了解一下如何使用。

### 条件队列的使用

直接看下条件队列相关的api，Object中的wait(),notify(),notifyAll()三个方法，大家应该很熟悉，如何使用呢？打开javadoc
```
synchronized (obj) {
    while (condition does not hold)
    obj.wait(timeout);
    // Perform action appropriate to condition
}
```
这个是wait()的例子，注释里还有这么几句话：

This method should only be called by a thread that is the owner of this object's monitor.
waits should always occur in loops
第一句话是说必须得持有线程锁，第二句话是wait()必须在一个循环中使用。javadoc中notify()和notifyAll()没有提供具体的例子，但是也有这么一句话

This method should only be called by a thread that is the owner of this object's monitor.
就是说需要当前线程持有对象锁时才能执行。再补充一些条件:

在线程之间共享对象上加锁
线程之间共享的对象调用wait(),notify()和notifyAll()
为什么有这几个要求呢？首先需要获取锁，是因为如果没有锁则会导致多个线程之间产生竞态条件，具体可以查看这边文章[Java的wait(), notify()和notifyAll()使用小结](http://www.cnblogs.com/techyc/p/3272321.html)；其次需要在循环里调用wait()，因为唤醒动作有可能是误操作，比如消费者生产者模式中，消费队列从空变为不为空和满变为不满，都会调用notifyAll()，但是在条件谓词（查看《java并发编程实战》）为true情况有两个：消费队列为空和消费队列已满。前面的notifyAll()会导致所有的wait set里的线程唤醒，如果条件谓词使用if会产生问题。补充的两个条件是为什么呢？下面继续说。

### 锁与条件队列
java线程同步是通过monitor机制来实现的，分为互斥执行和协作。下面贴张图说明一下java monitor的机制（这个图抄的，详细信息见[探索 Java 同步机制](https://www.ibm.com/developerworks/cn/java/j-lo-synchronized/)）


尝试获取锁的线程会进入entry set，获取锁就会变成锁的owner，调用wait()之后就会进入到wait set中，notify()唤醒wait set中的线程之后，对象会再次变为owner，如果条件谓词依旧成立则该线程再次进入到wait set，否则线程会继续执行，直到执行结束，释放锁。

### wait()、notify()和notifyAll()的实现

先介绍一下上一节介绍的monitor，HotSpot中的monitor结构如下：
```
ObjectMonitor() {
    _header       = NULL;
    _count        = 0;
    _waiters      = 0,
    _recursions   = 0;
    _object       = NULL;
    _owner        = NULL;
    _WaitSet      = NULL;
    _WaitSetLock  = 0 ;
    _Responsible  = NULL ;
    _succ         = NULL ;
    _cxq          = NULL ;
    FreeNext      = NULL ;
    _EntryList    = NULL ;
    _SpinFreq     = 0 ;
    _SpinClock    = 0 ;
    OwnerIsThread = 0 ;
  }
```
_WaitSet和_EntryList就是图中的wait set和entry list，条件队列的方法就是围绕着_WaitSet进行操作。_WaitSet和_EntryList存放的是ObjectWaiter，这是什么？这个对象存放thread，每个等待锁的线程都会有一个ObjectWaiter对象。现在开始查看这个三个方法的本地实现。

打开Object类找到这三个方法，发现都是native的，都是java的本地方法。打开openJdk的源码jdk-src-share-native-java-lang-Object.c，打开这个目录就能发现java的本地方法都是用c实现的，而jvm是用c++实现的。
```
static JNINativeMethod methods[] = {
    {"hashCode",    "()I",                    (void *)&JVM_IHashCode},
    {"wait",        "(J)V",                   (void *)&JVM_MonitorWait},
    {"notify",      "()V",                    (void *)&JVM_MonitorNotify},
    {"notifyAll",   "()V",                    (void *)&JVM_MonitorNotifyAll},
    {"clone",       "()Ljava/lang/Object;",   (void *)&JVM_Clone},
};
```
继续查看JVM_MonitorWait方法，在jvm.cpp里
```
JVM_ENTRY(void, JVM_MonitorWait(JNIEnv* env, jobject handle, jlong ms))
  JVMWrapper("JVM_MonitorWait");
  Handle obj(THREAD, JNIHandles::resolve_non_null(handle));
  assert(obj->is_instance() || obj->is_array(), "JVM_MonitorWait must apply to an object");
  JavaThreadInObjectWaitState jtiows(thread, ms != 0);
  if (JvmtiExport::should_post_monitor_wait()) {
    JvmtiExport::post_monitor_wait((JavaThread *)THREAD, (oop)obj(), ms);
  }
  ObjectSynchronizer::wait(obj, ms, CHECK);
JVM_END
```
重点是调用ObjectSynchronizer::wait()，该方法在synchronizer.cpp文件中，定义如下：
```
void ObjectSynchronizer::wait(Handle obj, jlong millis, TRAPS) {
  if (UseBiasedLocking) {
    BiasedLocking::revoke_and_rebias(obj, false, THREAD);
    assert(!obj->mark()->has_bias_pattern(), "biases should be revoked by now");
  }
  if (millis < 0) {
    TEVENT (wait - throw IAX) ;
    THROW_MSG(vmSymbols::java_lang_IllegalArgumentException(), "timeout value is negative");
  }
  ObjectMonitor* monitor = ObjectSynchronizer::inflate(THREAD, obj());
  DTRACE_MONITOR_WAIT_PROBE(monitor, obj(), THREAD, millis);
  monitor->wait(millis, true, THREAD);

  /* This dummy call is in place to get around dtrace bug 6254741.  Once
     that's fixed we can uncomment the following line and remove the call */
  // DTRACE_MONITOR_PROBE(waited, monitor, obj(), THREAD);
  dtrace_waited_probe(monitor, obj, THREAD);
}
```
这里可以看到上面ObjectMonitor对象，调用wait()，这个方法的代码就不贴了，先看下CHECK_OWNER()
```
#define CHECK_OWNER()                                                             \
  do {                                                                            \
    if (THREAD != _owner) {                                                       \
      if (THREAD->is_lock_owned((address) _owner)) {                              \
        _owner = THREAD ;  /* Convert from basiclock addr to Thread addr */       \
        _recursions = 0;                                                          \
        OwnerIsThread = 1 ;                                                       \
      } else {                                                                    \
        TEVENT (Throw IMSX) ;                                                     \
        THROW(vmSymbols::java_lang_IllegalMonitorStateException());               \
      }                                                                           \
    }                                                                             \
  } while (false)
```
这里可以看到如果条件队列的方法没有获取到锁就会抛IllegalMonitorStateException异常。

再看下AddWaiter()方法，就是把该线程的ObjectWaiter对象加入到_WaitSet中。

其次调用exit()方法，释放线程锁

最后park当前线程，把当前线程挂起。
```
if (millis <= 0) {
    Self->_ParkEvent->park () ;
} else {
    ret = Self->_ParkEvent->park (millis) ;
}
```
再看一下notify()，也在objectMonitor.cpp文件中，这里只说一下大概的过程，具体的逻辑自己查看代码。
跟wait()方法类似，先调用CHECK_OWNER()校验调用该方法之前是否有获取锁，其次从_WaitSet中dequeue一个ObjectWaiter对象，代码如下：
```
ObjectWaiter * iterator = DequeueWaiter() ;
```
余下逻辑的解释待补充

这里只是大概介绍了一下wait()，notify()和notifyAll()三个方法的底层实现，具体的逻辑还需要继续研究。

参考：

* [java 中的 wait 和 notify 实现的源码分析](http://blog.csdn.net/raintungli/article/details/6532784)
* [从零单排 Java concurrency, wait & notify](http://regrecall.github.io/2014/06/24/wait-notify/)
* [探索 Java 同步机制](https://www.ibm.com/developerworks/cn/java/j-lo-synchronized/)

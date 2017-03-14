---
title: final内存语义
date: 
tags:
---

最近重新阅读了一遍《java并发编程实战》的前面几个章节，在讲述不变性时，说到不可变对象一定是线程安全的，要保证类的不可变性，一个必要条件是：
> 对象的所有域都是final类型

先提出第一个问题， 保证对象的不变性，只要保证对象的域不能通过方法溢出就可以了，这样域用final域修饰也是没必要的，为什么这里一定要所有域都是final修饰？如下面的代码

```
public class ThreeStooges {

private Set<String> stooges = new HashSet<String>();

public ThreeStooges() {
    stooges.add("Moe");
    stooges.add("Larry");
    stooges.add("Curly");
}

public boolean isStooges(String name) {
    return stooges.contains(name);
}

}
```

这里的ThreeStooges是不可变的吗？在构造函数中初始化完成，唯一的方法isStooges(String name)也没有把对象的域逸出，看起来这个类是不可变的，这个问题先按下不表。
我们暂且认为对象的所有域都必须用final修饰这个条件是必要的，这个理解起来还是比较容易，final类型的域是不能修改的，因此可以达到类的各个域再初始化之后都不能改变，但是紧接着又提到这么一句话： 
> final域能确保初始化过程的安全性，从而可以不受限制的访问不可变对象，并在共享这些对象时无需同步。

对于final的安全初始化书中只是一句话带过，并没有详细描述final关键的内存语义。导致后面对类的不变性认识有偏差。再提出第二个问题，final是如何保证初始化的安全性的。从这个疑问入手，对final内存语义进行一个分析，弄清楚jvm是如何保证final域安全初始化的。

### final域的重排序规则
对于final域，编译器和处理器的重排序需要遵循以下两个规则：

* 在构造函数内对一个final域的写入，与随后把这个被构造对象的引用赋值给一个引用变量，这两个操作之间不能重排序。
    - JMM禁止编译器把final域的写重排序到构造函数之外。
    - 编译器会在final域的写之后，构造函数return之前，插入一个StoreStore屏障。这个屏障禁止处理器把final域的写重排序到构造函数之外。

* 初次读一个包含final域的对象的引用，与随后初次读这个final域，这两个操作之间不能重排序。
    - 在一个线程中，初次读对象引用与初次读该对象包含的final域，JMM禁止处理器重排序这两个操作（注意，这个规则仅仅针对处理器）。编译器会在读final域操作的前面插入一个LoadLoad屏障。

我们以x86处理器为例，说明final语义在处理器中的具体实现。写final域的重排序规则会要求译编器在final域的写之后，构造函数return之前，插入一个StoreStore障屏。读final域的重排序规则要求编译器在读final域的操作前面插入一个LoadLoad屏障。final域的重排序的规则详细查看[深入理解Java内存模型](http://www.infoq.com/cn/articles/java-memory-model-6)。

### 不变性分析
基于上面的分析我们再看一下上面两个问题。问题一中的ThreeStooges在当前的域和方法上是没有问题的，对象也是”暂时”不可变的，为什么要说是暂时？如果随着业务的扩展，我们需要增加一个字段或方法，修改后的代码如下所示：

```
public class ThreeStooges {

private Set<String> stooges = new HashSet<String>();
static ThreeStooges threeStooges;

public ThreeStooges() {
    stooges.add("Moe");
    stooges.add("Larry");
    stooges.add("Curly");
}

public boolean isStooges(String name) {
    ThreeStooges ts = threeStooges;
    return ts.isContain(name);
}

public void init() {
    threeStooges = new ThreeStooges();
}

public boolean isContain(String name) {
    return stooges.contain(name);
}

}
```
这个时候有两个线程分别调用init()和isStooges方法，从上一节的文章可知，init()方法在没有完全初始化时，也就是“Moe”、“Larry”、“Curly”没有add进stooges时，isStooges(String name)方法这时，name的值为"Larry"，查询到的stooges可能为空、也可能不为空，如果不为空时方法有可能返回true也可能返回false。此时stooges里的值可能是“More”、“Larry”和“Curly”的任意组合，产生此现象的原因就是初始化对象时的非final域会进行重排序，除了三个add()方法会进行重排序，add()方法也有可能重排序到对象对外可见之后。这样就回答了第一个问题，同时也解释了final的内存语义，final域可以保证初始化过程的安全性。
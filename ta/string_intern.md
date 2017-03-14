---
title: String.intern()解析
date: 
tags:
---

看下JDK的注释：
> When the intern method is invoked, if the pool already contains a string equal to this String object as determined by the equals(Object) method, then the string from the pool is returned. Otherwise, this String object is added to the pool and a reference to this String object is returned.

当调用String的intern()方法之后，会先检查常量池里是否包含该字符串，包含则直接返回，否则把该字符串放入到常量池里并返回该字符串。

### 为什么要使用String.intern()
我们先来看一段代码：

```
String a = "123";
String b = "12";
String c = b + "3";
System.out.println(a == c);
System.out.println(a == c.intern());
```
熟悉intern()的同学都知道这段代码会打印false和true，为什么呢？

从代码中我们知道变量a指向的“123”是存放在方法区的常量池中，jdk6的常量池在永久代，而从jdk7开始常量池就转移到了heap中（但是和普通heap中的字符串还是有区别的）。

我们分析一下第3行代码：

```
String c = b + "3";
```
通过javap查看上段代码的字节码：

```
0: ldc           #18                 // String 123
         2: astore_1
         3: ldc           #20                 // String 12
         5: astore_2
         6: new           #9                  // class java/lang/StringBuilder
         9: dup
        10: invokespecial #10                 // Method java/lang/StringBuilder."<init>":()V
        13: aload_2
        14: invokevirtual #14                 // Method java/lang/StringBuilder.append:(Ljava/lang/String;)Ljava/lang/StringBuilder;
        17: ldc           #21                 // String 3
        19: invokevirtual #14                 // Method java/lang/StringBuilder.append:(Ljava/lang/String;)Ljava/lang/StringBuilder;
        22: invokevirtual #16                 // Method java/lang/StringBuilder.toString:()Ljava/lang/String;
        25: astore_3
```

可以看到第3行代码是通过StringBuilder对象调用append()以及toString()生成的。由此我们可以知道变量c指向的是heap中的String对象，因此a == c返回false。而第二条语句中的c.intern()会到方法区中的常量池中看“123”常量是否存在，存在则直接返回，由于a变量指向的“123”已经在常量池中，所以会直接返回该常量，也就是说c.intern()返回的是常量池中“123”的引用，而不是heap中的String对象的引用，因此a == c.intern()返回true。

再来看一段代码：
```
String b = "12";
String c = b + "3";
c.intern();
String a = "123";
System.out.println(a == c);
```
现在会返回什么？jdk6是false，而jdk7之后是true，为什么？因为在jdk6中，c.intern()之后会把“123”放到常量池中，而不是c的引用；而jdk7中，c.intern()之后常量池中保存的是c在heap中的引用，后面a也会指向这个引用，因此输出true。

String.intern()有什么用？由上面分析我们知道在jdk7中，当首次String.intern()时，常量池中会直接保存该对象的引用，如果后面有相同值的String对象调用intern()，则直接返回该引用，而不会重新创建对象，从而达到较少内存的效果。那么我们是否应该在代码中对每个String对象都进行一次intern()的调用？答案是否定的，为什么？下面继续说。

### String.intern()的实现
我们查看String.intern()的代码，发现该方法是一个native的方法，我们可以从openJdk中找到相关的实现。

在openjdk/jdk/src/share/native/java/lang/String.c文件中可以看到如下代码实现：

```
JNIEXPORT jobject JNICALL
Java_java_lang_String_intern(JNIEnv *env, jobject this)
{
    return JVM_InternString(env, this);
}
```
openjdk/hotspot/src/share/vm/prims/jvm.cpp中可以看到JVM_InternString(env, this)的定义：

```
JVM_ENTRY(jstring, JVM_InternString(JNIEnv *env, jstring str))
  JVMWrapper("JVM_InternString");
  JvmtiVMObjectAllocEventCollector oam;
  if (str == NULL) return NULL;
  oop string = JNIHandles::resolve_non_null(str);
  oop result = StringTable::intern(string, CHECK_NULL);
  return (jstring) JNIHandles::make_local(env, result);
JVM_END
```
而StringTable::intern(string, CHECK_NULL)定义在openjdk/hotspot/src/share/vm/classfile/symbolTable.cpp中：

```
oop StringTable::intern(Handle string_or_null, jchar* name,
                        int len, TRAPS) {
  unsigned int hashValue = java_lang_String::hash_string(name, len);
  int index = the_table()->hash_to_index(hashValue);
  oop string = the_table()->lookup(index, name, len, hashValue);

  // Found
  if (string != NULL) return string;

  // Otherwise, add to symbol to table
  return the_table()->basic_add(index, string_or_null, name, len,
                                hashValue, CHECK_NULL);
}
```

这段代码和java中的HashMap类似，先求字符串的hash值，但是找到对应的index，并设置到该index对应的链表当中，但是c++中的StringTable不能自动扩容，因此如果常量过多，会导致Hash值严重冲突，导致链表过长，扫描链表的性能下降。

由上面的分析再来看上一节留下的问题，很明显intern()不能在所有String场景下使用，而是比较适合在String对象重复出现次数较多且字符串对象有限的场景使用，而重复较少，但是字符串过多的场景则不适合使用。滥用intern()方法造成的问题，下面的参考链接有具体说明。

参考：

* [深入解析String#intern](http://tech.meituan.com/in_depth_understanding_string_intern.html)
* [Java8内存模型—永久代(PermGen)和元空间(Metaspace)](http://www.cnblogs.com/paddix/p/5309550.html)
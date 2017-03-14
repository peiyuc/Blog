---
title: awk小技巧
date: 
tags:
---

在日常工作中，在不得已的情况我们可能需要根据日志统计一些业务信息，现介绍两种比较常用的功能，基于awk的统计和合并文件。
### 内建变量
* $0 当前记录（这个变量中存放着整个行的内容）
* $1 - $n 当前记录的第n个字段，字段间由FS分隔
* FS 输入字段分隔符 默认是空格或Tab
* NF 当前记录中的字段个数，就是有多少列
* NR 已经读出的记录数，就是行号，从1开始，如果有多个文件话，这个值也是不断累加中。
* FNR 当前记录数，与NR不同的是，这个值会是各个文件自己的行号
* RS 输入的记录分隔符， 默认为换行符
* OFS 输出字段分隔符， 默认也是空格
* ORS 输出的记录分隔符，默认为换行符
* FILENAME 当前输入文件的名字

### 统计
统计一列数字的和

```
ls -l *.cpp *.c *.h | awk '{sum+=$5} END {print sum}'
```
统计每个用户的进程占了多少内存

```
ps aux | awk 'NR!=1{a[$1]+=$6;} END { for(i in a) print i ", " a[i]"KB";}'
```
    
这两个统计方法平时用的比较多，对进行线上机器进行业务量统计的时候经常使用，可以多关注一下。

### 合并文件

在统计业务日志时，经常需要按列合并两个文件，比如有两个文件，文件age.txt为

```
Adams         20
Bush          30
Carter        27
```

包含姓名和年龄两个字段，

city.txt为

```
Adams         London
Bush          HongKong
Carter        Beijing
Sam　　　　　　 Nanjing
```

包含姓名和城市的两个字段，现在需要把这两个文件按照姓名合并成三列的文件，即文件info.txt：

```
Adams         London　　　　　 20
Bush          HongKong　　　　 30
Carter        Beijing　　　　  27
Sam　　　　　　 Nanjing　　　　　-　
```

没有年龄的用“-”代替。

awk语句：

```
awk 'NR==FNR{a[$1]=$2;next}NR>FNR{if ( $1 in a) print $0 "\t" a[$1]; else print $0 "\t" "0"}' city.txt age.txt > info.txt
```

解释：如果总行号等于分行号则构建map，如果大于则开始读第二个文件，第二个文件的第一个值在第一个文件中存在则打印第二个文件的行以及map中的值，不存在则用0代替，换句话说就是：

用第一个文件取构建map，再用第二个文件去取map里的值并和自己的值merge，形成新的文件，这里用到awk的内建变量NR和FNR

一般先读取记录数多的，再读取少的，这样构建的map的key才全，不至于在第二个文件里有的key，在map里找不到

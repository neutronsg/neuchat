# NeuChat Knownledge Base

1. 新增一级菜单：Knowledge Base

2. 下面是这个 account 关联的 knowledge base 的列表。怎么关联？rails console 后台关联(暂时不需要开放给用户，而且本身每个客户在 setup 时我们就需要做这些事情)。不过可能可以考虑做的是，不主动在 Dify 创建 dataset，而是等用户第一次使用这个功能的时候，我们才去调用 Dify 的 API 创建(需要看能不能支持，因为我看 Dify 后台是新建 dataset 要跟随上传一个 document 才可以)。

3. NeuChat 里面的 knowledge base 至少要有这些 columns：account id、name、neuai_dataset_id（string）

4. 对于每一个 NeuChat 的 knowledge base, 有 3 类数据源：
  1.	Documents，对应 Dify 的 Document
	2.	Q&As，对应也是 Dify 的 Document，NeuChat 的 UI 是每个 Q&A 独立管理的，但是我们最终会把所有的 Q&A 合成一个 string, 格式：
    Question: xxx
    Answer: xxx
    ------
    Question: xxx
    Answer: xxx
    ------
    ...
    然后调用 Dify 的接口更新到 Document, 需要注意用的 Dify 官方SaaS, 没有社区版本才有的 Q&A mode， 就是普通文档配合 High Quality + Delimiter '------' 实现的。
  3.	Web URLs
    •	TBD,还没搞清楚 Dify 的相关 API，你可以调研一下，推荐直接阅读 Dify 代码

5. Neuchat 是多租户的(Accounts), 而 Dify 我们只有一个 workspace，因为 Neuchat 的 knowledge base 是手动setup 创建的，天然隔离了。但是 Dify 这边可能需要用 tag 之类的来做区分。

6. 整体类似于把 Dify 知识库的管理半开放给客户，客户也不需要太复杂的配置和功能，所以 UI 尽量简单，不要有太多非必要选项。
但是比如，document 状态、开关这些可以考虑开放给用户。
    
Tips:
1. 当前项目就是 Neuchat，fork 自 chatwoot
2. Dify 项目我们 clone 到了 refs/dify 目录可以直接阅读参考，关于 Dify 的 API，需要严格参照 Dify 的代码(源码或者 docs)。
3. Knowledge 在 Dify 内部是 dataset
4. Dify 后台跟随第一 document 创建时才能创建一个 dataset，不知道对我们流程有没有影响
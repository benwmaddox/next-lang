# Sol: reusable definitions and pool ids

Ben, I recommend an explicit owner parameter, with scoped identities supplied by pools and batches. This completes the existing path-based design. All syntax below is illustrative.

Two layouts must stay distinct: mutable ids are **slot32 + generation32**; frozen ids are **partition32 + row32**. Neither contains an owner. Matching slot and generation in the wrong pool can find an unrelated live element. Generation checks alone cannot detect that mistake.

## 1. Element-typed ids, checked owners at run time

```
struct Node {
    parent: Option<Id<Node>>
    children: list<Id<Node>, 64>
}
var a: pool<Node, 4096>
var b: pool<Node, 4096>
b.get(a.add(Node { parent: none }).unwrap()) // WrongOwner
```

Definitions and helpers use ordinary element types. Two pools of `Rock` work naturally. The parser needs no owner parameters, and trees can pass through ordinary records and returns.

However, every id must carry enough information to distinguish owners, including owners whose storage was freed and reused. A straightforward representation adds an owner number, making ids larger, for example 128 bits. Lookups add an owner comparison; errors become run-time failures, ideally naming both pools, rather than build errors. Distinguish wrong-owner errors from stale-id `none` so bugs are visible.

Keeping 64 bits requires reducing the existing fields, or making the id an index into a separate registry containing owner, slot and generation. That registry adds storage, another lookup, bounds and reuse rules. Merely putting an owner number in the pool header cannot identify where an incoming 64-bit id originated. Frozen ids face the same space problem. Copies must issue or remap identities and internal links; this is additional work proportional to the copied graph.

## 2. An explicit owner parameter

An **owner parameter** is a placeholder for one particular collection's identity, checked during compilation and absent from stored data.

```
struct Node<P> {
    parent: Option<Id<P>>
    children: list<Id<P>, 64>
}
owner P                              // fresh, compiler-controlled identity
var nodes: pool<Node<P>, 4096, P>     // bind P to exactly this pool
fn parent<P, N>(nodes: pool<Node<P>, N, P>, id: Id<P>)
    -> Option<Id<P>> {
    let node = nodes.get(id) ?? return none
    node.parent
}
```

For mutable storage, the compiler must bind `P` to exactly one pool; users cannot attach it to another pool or cast between owners. `nodes.Id` remains shorthand for `Id<P>`. A **brand** means this unforgeable identity; **generative** means a fresh identity for each creation, even repeated calls at one source line. Parameters let helpers work with whichever owner the caller supplies. They do not require a separate compiled function for every file.

Ids remain 64 bits with existing checks and no owner comparison. `Id<P>` uses the mutable layout when P identifies a mutable pool, and the frozen layout when it identifies one row kind (such as Node) across a batch's partitions; the compiler keeps these kinds distinct. Diagnostics should say “expected nodes.Id; received other.Id,” show both declarations, and explain scope escapes using source names.

For S1, create `b` outside the parallel work; use `Node<b.Node>` and `Id<b.Node>` in every file's builder and helper. All partitions share that owner, enabling cross-file links. Freezing preserves ids without rewriting them. Different batches cannot mix. Named callbacks take owner-parameterised context explicitly, consistent with Functions as values; no capturing closure is needed.

This costs compiler support for owner inference, scope checks and owner-aware function contracts. Link-free `Rock` needs no parameter; a self-linked `Rock<P>` does.

## 3. One pool per element type per scope

```
struct Node { parent: Option<Id<Node>> }
scope {
    var nodes: pool<Node, 4096>        // Id<Node> means this pool
    var extra: pool<Node, 4096>        // build error: second Node pool
}
```

This keeps 64-bit ids and existing lookup costs by making ownership implicit. Errors about duplicate pools are simple, but nested scopes need precise rules: an id must retain its original meaning when passed elsewhere. Helpers and escaping values therefore still need hidden owner information in their types.

A per-file parser fits separate scopes, but collecting trees and cross-file links requires a special batch rule or explicit owners again. Two same-type Rock pools require wrapper types or separate scopes. That restriction would complicate ordinary programs to save a visible parameter.

## Recommendation and M2 boundary

Choose option 2. Specify copies and returns now: copying a self-contained pool creates a fresh destination owner and rebinds its internal self-links without changing id bits; external ids still name the source. Returns can build into the caller's destination with its owner. Helpers may return caller-owned ids, never ids of a pool that dies on return. Reject unsupported cross-linked copies explicitly.

Resetting a pool under the same owner must preserve generation history or be refused; zeroing generations revives stale ids. Before closing M2, require examples covering self-links, two same-type pools, helper returns, copying, reset rejection, and repeated creation. Reserve the same owner model for frozen batches.

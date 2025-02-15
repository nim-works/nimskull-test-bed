## This module contains the main definitions that make up the mid-end IR (MIR).
##
## See `MIR <mir.html>`_ for the grammar plus a high-level overview of the MIR.

import
  compiler/ast/[
    ast_types
  ],
  compiler/utils/[
    idioms
  ]

type
  LocalId* = distinct uint32
    ## Identifies a local inside a code fragment
  GlobalId* = distinct uint32
    ## Identifies a global across all MIR code
  ConstId* = distinct uint32
    ## Identifies a constant across all MIR code. This includes both
    ## user-defined constants as well as anonymous constants
  ParamId {.used.} = distinct uint32
    ## Identifies a parameter of the code fragment
  FieldId {.used.} = distinct uint32
    ## Identifies the field of a record type
  ProcedureId* = distinct uint32
    ## Identifies a procedure
  NumberId* = distinct uint32
    ## Uniquely identifies some numerical value (float, signed int,
    ## unsigned int). Two values with the same bit pattern have the same ID
  StringId* = distinct uint32
    ## Uniquely identifies a string value. Two strings sharing the same
    ## content map to the same ID
  AstId* = distinct uint32
    ## Identifies an AST fragment stored in the MIR environment.
  DataId* = distinct uint32
    ## Identifies a complete constant expression

  TypeId* = distinct uint32
    ## Identifies a type

  SourceId* = distinct range[0'u32 .. high(uint32)-1]
    ## The ID of a source-mapping that's stored separately from the MIR nodes.

# make ``SourceId`` available for use with ``OptIndex``:
template indexLike*(_: typedesc[SourceId]) = discard

type
  LabelId* = distinct uint32
    ## ID of a label, used to identify the control-flow destinations and
    ## constructs.

  MirNodeKind* = enum
    ## Users of ``MirNodeKind`` should not depend on the absolute or relative
    ## order between the enum values
    # when adding new enum values, make sure to adjust the sets below
    mnkNone

    # entity names:
    mnkProc   ## procedure reference; only allowed in callee slots
    mnkProcVal## procedural value
    mnkConst  ## named constant
    mnkGlobal ## global location
    mnkParam  ## parameter
    mnkLocal  ## local location
    mnkTemp   ## like ``mnkLocal``, but the local was introduced by the
              ## compiler during the MIR phase
    mnkAlias  ## local run-time handle. This is essentially a ``var T`` or
              ## ``lent T`` local

    mnkField  ## declarative node only allowed in special contexts
    mnkLabel  ## name of a label

    mnkNilLit  ## nil literal
    mnkIntLit  ## reference to signed integer literal
    mnkUIntLit ## reference to unsigend integer literal
    mnkFloatLit## reference to float literal
    mnkStrLit  ## reference to a literal string
    mnkAstLit  ## reference to AST fragment
    mnkType    ## a type literal

    # future direction:
    # store the type of the destination within each def, assignment, etc. and
    # then remove the type field from ``MirNode``

    mnkImmediate ## special node only allowed in certain contexts. Used to
                 ## store extra, context-dependent information in the tree

    mnkMagic  ## only allowed in a callee position. Refers to a magic
              ## procedure

    mnkResume    ## special action in a target list that means "resume
                 ## exception handling in caller"
    mnkLeave     ## a leave action within a target list
    mnkTargetList## describes the actions to perform prior to jumping, as well
                 ## as the final jump

    mnkDef       ## marks the start of existence of a local, global, procedure,
                 ## or temporary. Supports an optional intial value (except for
                 ## procedure definitions)
    mnkDefCursor ## marks the start of existence of a non-owning location

    mnkBind      ## introduces an alias that may be used for read/write
                 ## access, but not for direct assignments. The source
                 ## expression must not be empty
    mnkBindMut   ## introduces an alias that may be used for read/write access
                 ## and assignments. The source expression must not be empty

    mnkAsgn     ## normal assignment; the destination might store a value
                ## already. Whether the source is copied or moved depends
                ## on the expression
    mnkInit     ## similar to ``mnkAsgn``, but makes the guarantee that the
                ## destination contains no value (i.e., is not initialized).
                ## "Not initialized" doesn't make any guarantees about the
                ## destination's in-memory contents

    mnkSwitch ## sets the value of a discriminator field, changing the active
              ## branch, if necessary. The destination operand must be a
              ## ``mnkPathVariant`` expression

    mnkPathNamed ## access of a named field in a record
    mnkPathPos   ## access of a field in record via its position
    # future direction: merge ``mnkPathPos`` with ``mnkPathNamed``. This first
    # requires a dedicated MIR type representation.
    mnkPathArray ## access of an array-like (both dynamic and static) value
                 ## with an integer index
    mnkPathVariant ## access a tagged union
                   ## XXX: this is likely only a temporary solution. Each
                   ##      record-case part of an object should be its own
                   ##      dedicated object type, which can then be addressed
                   ##      as a normal field
    # future direction: merge ``mnkPathVariant`` into ``mnkPathNamed`` once the
    # MIR's record type structure supports this
    mnkPathConv  ## a handle conversion. That is, a conversion that produces a
                 ## *handle*, and not a new *value*. At present, this operator
                 ## also applies to first-class handles, like ``ref``.

    mnkAddr   ## create a pointer from the provided lvalue
    mnkDeref  ## dereference a ``ptr`` or ``ref`` value

    mnkView      ## create a first-class safe alias from an lvalue
    mnkMutView   ## create a safe mutable view from an lvalue
    mnkDerefView ## dereference a first-class safe alias

    mnkStdConv    ## a standard conversion. Produce a new value.
    mnkConv       ## ``conv(x)``; a conversion. Produces a new value.
    # future direction: replace both conversion operators with ``NumberConv``.
    # String-to-cstring conversion, and vice versa, should use magics, pointer
    # conversion should use ``mnkCast``
    mnkCast       ## cast the representation of a value into a different type
    mnkToSlice    ## has to variants:
                  ## * the 1 argument variant creates an openArray from the
                  ##   full sequence specified as the operand
                  ## * the 3 argument variant creates an openArray from the
                  ##   sub-sequence specified by the sequence and lower and
                  ##   upper bound
    # XXX: consider using a separate operator for the slice-from-sub-sequence
    #      operation
    mnkToMutSlice ## version of ``mnkToSlice`` for creating a mutable slice

    mnkCall   ## invoke a procedure and pass along the provided arguments.
              ## Used for both static and dynamic calls
    mnkCheckedCall  ## invoke a magic procedure and pass along the provided arguments

    # unary arithmetic operations:
    mnkNeg ## signed integer and float negation (for ints, overflow is UB)
    # binary arithmetic operations:
    mnkAdd ## signed integer and float addition (for ints, overflow is UB)
    mnkSub ## signed integer and float subtraction (for ints, overflow is UB)
    mnkMul ## signed integer and float multiplication (for ints, overflow is
           ##  UB)
    mnkDiv ## signed integer and float division (for ints, division by zero is
           ## UB)
    mnkModI ## compute the remainder of an integer division (division by zero
            ## is UB)
    # future direction: the arithmetic operations should also apply to
    # unsigned integers

    mnkRaise  ## if the operand is an ``mnkNone`` node, reraises the
              ## currently active exception. Otherwise, consumes the operand
              ## and sets it as the active exception

    mnkSetConstr  ## constructor for set values
    mnkRange      ## range constructor. May only appear in set constructions
                  ## and as a branch label
    mnkArrayConstr## constructor for array values
    mnkSeqConstr  ## constructor for seq values
    mnkTupleConstr## constructor for tuple values
    mnkClosureConstr## constructor for closure values
    mnkObjConstr  ## constructor for object values
    mnkRefConstr  ## allocates a new managed heap cell and initializes it
    mnkBinding    ## only valid as an object or ref construction child node.
                  ## Associates an argument with a field

    mnkCopy   ## denotes the assignment as copying the source value
    mnkMove   ## denotes the assignment as moving the value. This does
              ## not imply a phyiscal change to the source location
    mnkSink   ## collapses into one of the following:
              ## - a copy (`mnkCopy`)
              ## - a non-destructive move (`mnkMove`)
              ## - a destructive move
              ##
              ## Collapsing ``mnkSink`` is the responsibility of the move
              ## analyzer.

    mnkArg    ## when used in a call: denotes an argument that may either be
              ## passed by value or by name. Evaluation order is unspecified
              ## when used in a construction: denotes a value that is copied
              ## (shallow) into the aggregate value
    mnkName   ## denotes an argument that is passed by name
    mnkConsume## similar to ``mnkArg``, but moves (non-destructively) the
              ## value into the aggregate or parameter

    mnkVoid   ## either a:
              ## * syntactic statement node for representing void calls
              ## * statement acting as a use of the given lvalue

    mnkScope  ## starts a scope, which are used to delimit lifetime of locals
              ## they enclose. Can be nested, but must always be paired with
              ## exactly one ``mnkEndScope`` statement
    mnkEndScope## closes the current scope. Must always be paired with a
              ## ``mnkScope`` statement
    # future direction: both mnkScope and mnkEndScope should become atoms

    mnkGoto   ## unconditional jump
    mnkIf     ## depending on the run-time value of `x`, transfers control-
              ## flow to either the start or the end of the spanned code
    mnkCase   ## dispatches to one of its branches based on the run-time
              ## value of the operand
    mnkBranch ## a branch in a ``mnkCase`` dispatcher
    mnkLoop   ## unconditional jump to the associated-with loop start

    mnkJoin   ## join point for gotos and branches
    mnkLoopJoin## join point for loops. Represents the start of a loop
    mnkExcept ## starts an exception handler
    mnkFinally## starts a finally section. Must be paired with exactly one
              ## ``mnkContinue`` that follows
    mnkContinue## marks the end of a finally section
    mnkEndStruct ## marks the end of an if or except

    mnkDestroy## destroys the value stored in the given location, leaving the
              ## location in an undefined state

    mnkAsm    ## embeds backend-dependent code directly into the output
    mnkEmit   ## embeds backend-dependent code directly into the output

  EffectKind* = enum
    ekNone      ## no effect
    ekMutate    ## the value in the location is mutated
    ekReassign  ## a new value is assigned to the location
    ekKill      ## the value is removed from the location (without observing
                ## it), leaving the location empty
    ekInvalidate## all knowledge and assumptions about the location and its
                ## value become outdated. The state of it is now completely
                ## unknown

  MirNode* = object
    typ*: TypeId ## valid for all expression, including all calls
    info*: SourceId
      ## non-critical meta-data associated with the node (e.g., origin
      ## information)
    case kind*: MirNodeKind
    of mnkProc, mnkProcVal:
      prc*: ProcedureId
    of mnkGlobal:
      global*: GlobalId
    of mnkConst:
      cnst*: ConstId
    of mnkParam, mnkLocal, mnkTemp, mnkAlias:
      local*: LocalId
    of mnkField:
      field*: int32
        ## field position
    of mnkIntLit, mnkUIntLit, mnkFloatLit:
      number*: NumberId
    of mnkStrLit:
      strVal*: StringId
    of mnkAstLit:
      ast*: AstId
    of mnkLabel, mnkLeave:
      label*: LabelId
    of mnkImmediate:
      imm*: uint32 ## meaning depends on the context
    of mnkMagic:
      magic*: TMagic
    of mnkNone, mnkNilLit, mnkType, mnkResume:
      discard
    of {low(MirNodeKind)..high(MirNodeKind)} - {mnkNone .. mnkLeave}:
      len*: uint32

  MirTree* = seq[MirNode]
  MirNodeSeq* = seq[MirNode]
    ## A buffer of MIR nodes without any further meaning

  NodeIndex* = uint32
  NodePosition* = distinct int32
    ## refers to a ``MirNode`` of which the position relative to other nodes
    ## has meaning. Uses a signed integer as the base
  OpValue* = distinct uint32
    ## refers to an node appearing in an expression/operand position

  ArgKinds = range[mnkArg..mnkConsume]
    ## helper type to make writing exhaustive case statement easier

const
  AllNodeKinds* = {low(MirNodeKind)..high(MirNodeKind)}
    ## Convenience set containing all existing node kinds

  DefNodes* = {mnkDef, mnkDefCursor, mnkBind, mnkBindMut}
    ## Node kinds that represent definition statements (i.e. something that
    ## introduces a named entity)

  AtomNodes* = {mnkNone..mnkLeave}
    ## Nodes that don't support sub nodes.

  SubTreeNodes* = AllNodeKinds - AtomNodes
    ## Nodes that start a sub-tree. They always store a length.

  SingleOperandNodes* = {mnkPathNamed, mnkPathPos, mnkPathVariant, mnkPathConv,
                         mnkAddr, mnkDeref, mnkView, mnkDerefView, mnkStdConv,
                         mnkConv, mnkCast, mnkRaise, mnkArg,
                         mnkName, mnkConsume, mnkVoid, mnkCopy, mnkMove,
                         mnkSink, mnkDestroy, mnkMutView, mnkToMutSlice}
    ## Nodes that start sub-trees but that always have a single sub node.

  ArgumentNodes* = {mnkArg, mnkName, mnkConsume}
    ## Nodes only allowed in argument contexts.

  ModifierNodes* = {mnkCopy, mnkMove, mnkSink}
    ## Assignment modifiers. Nodes that can only appear directly in the source
    ## slot of assignments.

  LabelNodes* = {mnkLabel, mnkLeave}

  LiteralDataNodes* = {mnkNilLit, mnkIntLit, mnkUIntLit, mnkFloatLit,
                       mnkStrLit, mnkAstLit}

  ConstrTreeNodes* = {mnkSetConstr, mnkRange, mnkArrayConstr, mnkSeqConstr,
                      mnkTupleConstr, mnkClosureConstr, mnkObjConstr,
                      mnkRefConstr, mnkProcVal, mnkArg, mnkField,
                      mnkBinding} +
                     LiteralDataNodes
    ## Nodes that can appear in the MIR subset used for constant expressions.

  StmtNodes* = {mnkScope, mnkGoto, mnkIf, mnkCase, mnkLoop, mnkJoin,
                mnkLoopJoin, mnkExcept, mnkFinally, mnkContinue, mnkEndStruct,
                mnkInit, mnkAsgn, mnkSwitch, mnkVoid, mnkRaise, mnkDestroy,
                mnkEmit, mnkAsm, mnkEndScope} + DefNodes
    ## Nodes that are treated like statements, in terms of syntax.

  # --- semantics-focused sets:

  Atoms* = {mnkNone .. mnkType} - {mnkField, mnkProc, mnkLabel}
    ## Nodes that may be appear in atom-expecting slots.

  UnaryOps*  = {mnkNeg}
    ## All unary operators
  BinaryOps* = {mnkAdd, mnkSub, mnkMul, mnkDiv, mnkModI}
    ## All binary operators

  LvalueExprKinds* = {mnkPathPos, mnkPathNamed, mnkPathArray, mnkPathVariant,
                      mnkPathConv, mnkDeref, mnkDerefView, mnkTemp, mnkAlias,
                      mnkLocal, mnkParam, mnkConst, mnkGlobal}
  RvalueExprKinds* = {mnkType, mnkProcVal, mnkConv, mnkStdConv, mnkCast,
                      mnkAddr, mnkView, mnkMutView, mnkToSlice,
                      mnkToMutSlice} + UnaryOps + BinaryOps + LiteralDataNodes
  ExprKinds* =       {mnkCall, mnkCheckedCall, mnkSetConstr, mnkArrayConstr,
                      mnkSeqConstr, mnkTupleConstr, mnkClosureConstr,
                      mnkObjConstr, mnkRefConstr} + LvalueExprKinds +
                     RvalueExprKinds + ModifierNodes

  CallKinds* = {mnkCall, mnkCheckedCall}

func `==`*(a, b: SourceId): bool {.borrow.}
func `==`*(a, b: LocalId): bool {.borrow.}
func `==`*(a, b: LabelId): bool {.borrow.}
func `==`*(a, b: ConstId): bool {.borrow.}
func `==`*(a, b: GlobalId): bool {.borrow.}
func `==`*(a, b: ProcedureId): bool {.borrow.}
func `==`*(a, b: DataId): bool {.borrow.}
func `==`*(a, b: NumberId): bool {.borrow.}
func `==`*(a, b: StringId): bool {.borrow.}
func `==`*(a, b: AstId): bool {.borrow.}
func `==`*(a, b: TypeId): bool {.borrow.}

func isAnon*(id: ConstId): bool =
  ## Returns whether `id` represents an anonymous constant.
  (uint32(id) and (1'u32 shl 31)) != 0

func extract*(id: ConstId): DataId =
  ## Extracts the ``DataId`` from `id`.
  DataId(uint32(id) and not(1'u32 shl 31))

func toConstId*(id: DataId): ConstId =
  ## Creates the ID for an anonymous constant with `id` as the content.
  ConstId((1'u32 shl 31) or uint32(id))

# XXX: ideally, the arithmetic operations on ``NodePosition`` should not be
#      exported. How the nodes are stored should be an implementation detail

template `-`*(a: NodePosition, b: int): NodePosition =
  NodePosition(ord(a) - b)

template `+`*(a: NodePosition, b: int): NodePosition =
  NodePosition(ord(a) + b)

template `dec`*(a: var NodePosition) =
  dec int32(a)

template `inc`*(a: var NodePosition) =
  inc int32(a)

func `<`*(a, b: NodePosition): bool {.borrow, inline.}
func `<=`*(a, b: NodePosition): bool {.borrow, inline.}
func `==`*(a, b: NodePosition): bool {.borrow, inline.}

func `in`*(p: NodePosition, tree: MirTree): bool {.inline.} =
  ord(p) >= 0 and ord(p) < tree.len

template `[]`*(tree: MirTree, i: NodePosition | OpValue): untyped =
  tree[ord(i)]

template isAtom(kind: MirNodeKind): bool =
  # much faster than an `in SubTreeNodes` test
  ord(kind) <= ord(mnkLeave)

func parent*(tree: MirTree, n: NodePosition): NodePosition =
  result = n
  # walk backwards and compute the total number of nodes covered so far.
  # Once the covered region includes the node we started at, we've found the
  # parent
  var covered = 0'u32
  while true:
    dec result

    let node = tree[result]
    if not isAtom(node.kind):
      covered += node.len

    if uint32(result) + covered >= uint32(n):
      break

func sibling*(tree: MirTree, n: NodePosition): NodePosition =
  ## Computes the index of the next node/sub-tree following the node at `n`.
  # XXX: `sibling` is a misnomer; `next` would be more fitting
  result = n
  var last = n
  while result <= last:
    let node = tree[result]
    if not isAtom(node.kind):
      inc last, node.len.int
    inc result

func previous*(tree: MirTree, n: NodePosition): NodePosition =
  ## Computes the index of `n`'s the preceding sibling node. If there
  ## is none, returns the index of the parent node. **This is a slow
  ## operation, it should be used sparsely.**
  # XXX: could be optimized to not require first seeking to the parent
  result = tree.parent(n)
  var next = result + 1 # first child node
  # advance the position until the sibling is `n`
  while next < n:
    result = next
    next = tree.sibling(result)

func computeSpan*(tree: MirTree, n: NodePosition): Slice[NodePosition] =
  ## If `n` refers to a leaf node, returns a span with the `n` as the single
  ## item.
  ## Otherwise, computes and returns the span of nodes part of the sub-tree
  ## at `n`. The 'end' node is included.
  result = n .. (sibling(tree, n) - 1)

func child*(tree: MirTree, n: NodePosition, index: Natural): NodePosition =
  ## Returns the position of the child node at index `index`. `index` *must*
  ## refer to a valid sub-node -- no validation is performed
  assert tree[n].kind in SubTreeNodes
  result = n + 1 # point `result` to the first child
  for _ in 0..<index:
    result = sibling(tree, result)

func operand*(tree: MirTree, n: NodePosition, i: Natural): OpValue {.inline.} =
  ## Returns the `i`-th operand to the sub-tree at `n`. It is expected that
  ## the operation has at least `i` + 1 operands.
  OpValue child(tree, n, i)

func `[]`*(tree: MirTree, n: NodePosition, index: Natural): lent MirNode =
  ## Returns the `index`-th child node of sub-tree `n`.
  tree[child(tree, n, index)]

func `[]`*(tree: MirTree, n: OpValue, index: Natural): lent MirNode =
  ## Returns the `index`-th child node of sub-tree `n`.
  tree[child(tree, NodePosition n, index)]

func last*(tree: MirTree, n: NodePosition): NodePosition =
  ## Returns the last child node in the subtree at `n`.
  let skip = tree[n].len - 1
  result = tree.child(n, 0)
  for _ in 0..<skip:
    result = tree.sibling(result)

func findParent*(tree: MirTree, start: NodePosition,
                 kind: MirNodeKind): NodePosition =
  ## Searches for the first enclosing sub-tree node of kind `kind` (which is
  ## *required* to exist). The node at `start` is itself also considered
  ## during the search
  assert kind in SubTreeNodes
  result = start
  while tree[result].kind != kind:
    result = parent(tree, result)

func len*(tree: MirTree, n: NodePosition): int =
  ## Computes the number of child nodes for the given sub-tree node.
  tree[n].len.int

func numArgs*(tree: MirTree, n: NodePosition): int =
  ## Counts and returns the number of *call arguments* in the call tree at
  ## `n`.
  assert tree[n].kind in CallKinds
  result = tree[n].len.int - 2 - ord(tree[n].kind == mnkCheckedCall)

func operand*(tree: MirTree, op: OpValue|NodePosition): OpValue =
  ## Returns the index (``OpValue``) of the operand for the single-operand
  ## operation at `op`.
  let pos =
    when op is NodePosition: op
    else:                    NodePosition(op)
  case tree[op].kind
  of SingleOperandNodes - {mnkName}:
    OpValue(pos + 1)
  of mnkName:
    OpValue(pos + 2)
  else:
    unreachable()

func argument*(tree: MirTree, n: NodePosition, i: Natural): OpValue =
  ## Returns the `i`-th argument in the call-like tree at `n`, skipping
  ## tag nodes. It is expected that the call has at least `i` + 1
  ## arguments.
  assert tree[n].kind in CallKinds
  result = tree.operand(tree.child(n, 2 + i))

func skip*(tree: MirTree, n: OpValue, kind: MirNodeKind): OpValue =
  ## If `n` is of `kind`, return its operand node, `n` otherwise.
  if tree[n].kind == kind: tree.operand(n)
  else:                    n

iterator pairs*(tree: MirTree): (NodePosition, lent MirNode) =
  var i = 0
  let L = tree.len
  while i < L:
    yield (i.NodePosition, tree[i])
    inc i

iterator subNodes*(tree: MirTree, n: NodePosition; start = 0): NodePosition =
  ## Returns in order of apperance all direct child nodes of `n`, starting with
  ## `start`.
  let L = tree[n].len
  var n = tree.child(n, start)
  for _ in 0..<L:
    yield n
    n = tree.sibling(n)

iterator arguments*(tree: MirTree, n: NodePosition): (ArgKinds, EffectKind, OpValue) =
  ## Returns the argument kinds together with the operand node (or tag tree).
  assert tree[n].kind in CallKinds
  # the jump target of checked calls is not an argument
  let len = tree[n].len.int - ord(tree[n].kind == mnkCheckedCall)
  var i = tree.child(n, 2) # skip the callee and effect node
  for _ in 2..<len:
    let node = tree[i]
    let eff =
      case node.kind
      of mnkName: tree[i + 1].imm.EffectKind
      else:       ekNone
    # for efficiency, only use a single yield
    yield (ArgKinds(node.kind), eff, tree.operand(i))
    i = tree.sibling(i)

func findDef*(tree: MirTree, n: NodePosition): NodePosition =
  ## Finds and returns the first definition for the name of the temporary
  ## at node `n`. No control-flow analysis is performed.
  assert tree[n].kind in {mnkTemp, mnkAlias}
  let expected = tree[n].local
  # first, unwind until the closest statement
  result = n
  while tree[result].kind notin StmtNodes:
    result = tree.parent(result)

  # then search for the definition statement
  while result > NodePosition 0:
    if tree[result].kind in DefNodes:
      let name = tree.operand(result, 0)
      if tree[name].kind in {mnkTemp, mnkAlias} and
         tree[name].local == expected:
        return

    # seek to the previous statement:
    dec result
    while tree[result].kind notin StmtNodes:
      dec result

  unreachable("no corresponding def found")

# XXX: ``lpairs`` is not at all related to the mid-end IR. The ``pairs``
#      iterator from the stdlib should be changed to use ``lent`` instead
iterator lpairs*[T](x: seq[T]): (int, lent T) =
  var i = 0
  let L = x.len
  while i < L:
    yield (i, x[i])
    inc i

# -------------------------------
# queries for specific node kinds

func callee*(tree: MirTree, n: NodePosition): NodePosition {.inline.} =
  ## Returns the callee node for the call subtree `n`.
  assert tree[n].kind in CallKinds
  n + 2

proc mutatesGlobal*(tree: MirTree, n: NodePosition): bool {.inline.} =
  ## Whether evaluating the call expression at `n` potentially mutates
  ## global state.
  assert tree[n].kind in CallKinds
  tree[n, 0].imm.bool

func effect*(tree: MirTree, n: NodePosition): EffectKind {.inline.} =
  ## Returns the effect for the ``mnkName`` node at `n`.
  assert tree[n].kind == mnkName
  tree[n, 0].imm.EffectKind

func field*(tree: MirTree, n: NodePosition): int32 {.inline.} =
  ## Returns the field position specified for the field access at `n`.
  assert tree[n].kind in {mnkPathNamed, mnkPathVariant}
  tree[n, 1].field

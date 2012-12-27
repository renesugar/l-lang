(* Copyright 2012 Matthieu Lemerre.  *)
(* Cpsdef: definitions of data types for CPS representation. *)


(* \subsection*{Variables} *)

(*s The definition or variables and occurrences originate from
  [Cpsvar]. Note that [Cpsvar] makes variables and occurrences
  unique, avoiding any need for alpha conversion. *)

type var = (var_desc,occur_desc) Cpsvar.variable
and occur =  (var_desc,occur_desc) Cpsvar.occurrence
and cont_var = (cont_var_desc,cont_occur_desc) Cpsvar.variable
and cont_occur =  (cont_var_desc,cont_occur_desc) Cpsvar.occurrence

(* \subsection*{Expressions} *)

and term_ =
  | Let_prim of var * primitive *  term
  | Let_cont of cont_var * var * term * term
  | Apply_cont of cont_occur * occur
  | Apply of occur * cont_occur * occur
  | Halt of occur

and primitive =
  | Value of value
  | Projection of occur * int
  | Integer_binary_op of Constant.integer_binary_op * occur * occur
  | Integer_comparison of Constant.Icmp.predicate * occur * occur

(*i Note: it is unclear now whether it is interesting to put these
  values together in a value data type, or split them directly in the
  "primitive" data structure. It depends on whether we can take
  advantage of the definition of "value", i.e. values need no further
  computations; but this is not truly the case for tuples and
  lambdas, which may require dynamic allocation. i*)
(*i TODO: We should have separate "Lambda" and "Function" primitives
  (that may not be in values, but directly in primitives). The goal
  of lambda-lifting would be to remove all lambda primitives, while
  still allowing to obtain Functions directly from the source code,
  e.g. when interfacing with C code. i*)
and value =
  | Void
  | Constant of Constant.t
  | Tuple of occur list
  | Lambda of cont_var * var *  term

(* \subsection*{Definitions representation} *)



(*i The problem of top-level definitions is that a definition is really
   like a term, except that the variable that it binds is global. This
   introduce some redundancies, in particular concerning handling
   backlinks from terms to their parent terms or definitions. The
   definition structure is thus likely to be heavily changed, or even
   disappear in favor of an extended notion of "top-level term". i*)
and modul = Module of toplevel list
and toplevel = Top of definition list
and definition = Definition of visibility * definition_type
and visibility = Public of var | Private of var | Unused
and definition_type =
  | Function of var list * term
  | Static_value of value
  | Dynamic_value of term
  | External_value

(* \subsection*{Backlinks and mutability for efficient operations} *)

(*s The [term_] type defines the logical structure of a term, and we
  insert this structure between any two [term_]s, or between a [term_]
  and its [definition]. It implements a mutable double-link between a
  term and its parent, (which can be a term or a top-level
  definition).

  Note that a term has only one parent, and thus can appear only once
  in a tree. *)
and term = { mutable enclosing:enclosing; mutable term:term_ option}

and enclosing =
  | Enclosing_definition of definition
  | Enclosing_term of term
  | Enclosing_uninitialized

(*s For now we have only implemented uplinks from variables to their
  binding sites. We should hade uplinks from occurrences to the site
  that use them, and do the same for continuation variables.  *)
and var_desc = { mutable binding_site_var:enclosing; }
and occur_desc = unit
and cont_var_desc = unit
and cont_occur_desc = unit


(* \subsection*{Instantiations of [Cpsvar]} *)


module type VAR_RW = sig
  type var
  type occur
  module Var: sig
    val make : unit -> var
    val init: var -> enclosing -> unit
    type occurrence_number =
      | No_occurrence
      | One_occurrence of occur
      | Several_occurrences
    val occurrence_number: var -> occurrence_number
    val fold_on_occurrences: var -> 'a -> ('a -> occur -> 'a) -> 'a
    val replace_with: var -> var -> unit
    val to_string : var -> string
    val binding_site: var -> enclosing
    val set_binding_site: var -> enclosing -> unit
    module Map : Map.S with type key = var
    module Set : Set.S with type elt = var
  end

  module Occur: sig
    val make : var -> occur
    val delete: occur -> unit
    val binding_variable : occur -> var
    val to_string : occur -> string
    module Map : Map.S with type key = occur
    module Set : Set.S with type elt = occur
  end
end


module Var_ = Cpsvar.Make(struct
  type variable_description = var_desc
  type occurrence_description = occur_desc
  let var_prefix = "x"
end);;

module Cont_var_ = Cpsvar.Make(struct
  type variable_description = unit
  type occurrence_description = unit
  let var_prefix = "k"
end);;

module Var = struct
  type var = Var_.var
  type occur = Var_.occur
  module Var = struct
    include Var_.Var
    let binding_site v =
      let desc = Var_.Var.description v in
      desc.binding_site_var;;

    let init v e =
      Var_.Var.set_description v { binding_site_var=e};;

    (* Note that [set_binding_site] requies that
       [Var_.Var.description] exists, i.e. that [init] was called. *)
    let set_binding_site v e =
      let desc = Var_.Var.description v in
      desc.binding_site_var <- e;;

  end
  module Occur = Var_.Occur
end

module Cont_var = struct
  type var = Cont_var_.var
  type occur = Cont_var_.occur
  module Var = struct
    include Cont_var_.Var
    let binding_site v
        = failwith "binding_site for continuation variables not implemented";;

    let set_binding_site v e
        = failwith "binding_site for continuation variables not implemented";;

    let init v e = ();;

  end
  module Occur = Cont_var_.Occur
end


(* \subsection*{The [Term], [Empty], and [Fresh] modules} *)

(* Definitions common to [Term], [Fresh], et [Empty]. *)
module Common = struct
  let get t = match t.term with Some(t_) -> t_ | None -> assert false;;
  let set t t_ = t.term <- Some t_;;
  let empty t = t.term <- None;;
  let is_empty t = t.term == None;;

  let enclosing t = t.enclosing;;
  let set_enclosing t e = t.enclosing <- e;;
  let delete_enclosing t = t.enclosing <- Enclosing_uninitialized;;
  let is_fresh t = t.enclosing == Enclosing_uninitialized;;
end;;


module Empty = struct

  type t = term

  let is_empty = Common.is_empty;;
  let empty term =
    assert( not( is_empty term));
    Common.empty term;
    term;;

  let set t t_ =
    assert( is_empty t);
    Common.set t t_;;
  let fill t t_ = set t t_; t;;
end

module Fresh = struct

  type t = term

  let make t_ = { term = Some t_;
                  enclosing = Enclosing_uninitialized }
  let is_fresh = Common.is_fresh;;

  let get t = assert( is_fresh t); Common.get t

  let set_enclosing t e = assert( is_fresh t); Common.set_enclosing t e;
end

module Term = struct
  let get = Common.get
  let set = Common.set

  let enclosing = Common.enclosing;;
  let set_enclosing = Common.set_enclosing;;

  let make ?reconnect t_ = match reconnect with
    | None -> Fresh.make t_
    | Some(t) -> Empty.fill t t_
  ;;

  let discard term =
    Common.delete_enclosing term;
    Common.empty term
  ;;

end

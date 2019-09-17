open Batteries

let tok_to_const = function
  | Tok.Int i -> Ast.(Const (Int i))
  | Tok.Char c -> Ast.(Const (Char c))
  | _ -> failwith "Not a constant"

(* A map from a token to its corresponding Ast.binop.
 * Note that some tokens also correspond to other, non-binop
 * AST elements (e.g. Tok.Minus can also be parsed as unary minus),
 * so only use this map when we're expecting a binop *)
let op_map =
  Map.empty
  |> Map.add Tok.Plus Ast.Add
  |> Map.add Tok.Minus Ast.Sub
  |> Map.add Tok.Mult Ast.Mult
  |> Map.add Tok.Div Ast.Div
  |> Map.add Tok.Mod Ast.Mod
  |> Map.add Tok.Lt Ast.Lt
  |> Map.add Tok.Le Ast.Le
  |> Map.add Tok.Gt Ast.Gt
  |> Map.add Tok.Ge Ast.Ge
  |> Map.add Tok.DoubleEq Ast.Eq
  |> Map.add Tok.Neq Ast.Neq
  |> Map.add Tok.And Ast.And
  |> Map.add Tok.Or Ast.Or
  |> Map.add Tok.ShiftLeft Ast.ShiftL
  |> Map.add Tok.ShiftRight Ast.ShiftR
  |> Map.add Tok.BitAnd Ast.BitAnd
  |> Map.add Tok.BitOr Ast.BitOr
  |> Map.add Tok.Xor Ast.Xor

(**
 * Parse one production rule for a binary operation.
 * One production rule in the grammar corresponds to a particular precedence level.
 * Parameters:
 * - parse_next_level is a function to parse expressions
 *   at the next highest precedence level.
 * - op_toks is the list of tokens that should be parsed at this precedence level.
 * - toks is the tokenized source code to parse
 * For example, to parse the production rule for addition and subtraction:
 * <additive-exp> ::= <term> { ("+" | "-") <term> }
 * We would invoke this function as follows:
 * parse_bin_exp parse_term [Tok.Plus; Tok.Minus] toks
 **)
let parse_expression toks =
  let parse_bin_exp parse_next_level op_toks toks =
    (* call parse_next_level to parse first sub-expression *)
    let left, rest = parse_next_level toks in
    let rec add_terms left_exp toks =
      let hd_tok = List.hd toks in
      if (List.mem hd_tok op_toks) then
        (* The first token after left_exp is an operator we care about,
         * so there must be another sub-expression *)

        (* Parse the next sub-expression *)
        let right_exp, rest = parse_next_level (List.tl toks) in
        let bin_op = Map.find hd_tok op_map in
        (* Construct BinOp AST node BEFORE parsing additional sub-expressions.
         * This enforces left-associativity. *)
        let left_exp = Ast.BinOp (bin_op, left_exp, right_exp) in
        (* Try to parse more sub-expressions *)
        add_terms left_exp rest
      else
        (* No more sub-expressions to add, return current exp *)
        left_exp, toks
    in
    (* try adding more subexpressions *)
    add_terms left rest
  in

  let rec parse_function_call = function
    | Tok.(Id name::OpenParen::arg_tokens) ->
       let fun_name = Ast.ID(name) in
       let args, rest = parse_function_arguments arg_tokens in
       Ast.FunCall(fun_name, args), rest
    | _ -> failwith "Shouldn't have called parse_function_call, this isn't a function call"

  and parse_function_arguments = function
    | Tok.CloseParen::rest -> [], rest
    | toks ->
       let arg, rest = parse_exp toks in
       let args, rest =
         match rest with
         | Tok.Comma::more_args -> parse_function_arguments more_args
         | Tok.CloseParen::after_fun_call -> [], after_fun_call
         | _ -> failwith "Invalid list of function arguments"
       in
       arg::args, rest

  and parse_factor toks =
    let open Tok in
    match toks with
    | OpenParen::factor ->
       let exp, after_exp = parse_exp factor in
       begin
         match after_exp with
         | CloseParen::rest -> (exp, rest)
         | _ -> failwith "Syntax error: expected close paren"
       end
    | Minus::factor ->
       let num, rest = parse_factor factor in
       Ast.(UnOp (Negate, num)), rest
    | Plus::factor ->
       let num, rest = parse_factor factor in
       Ast.(UnOp (Pos, num)), rest
    | Complement::factor ->
       let num, rest = parse_factor factor in
       Ast.(UnOp (Complement, num)), rest
    | Bang::factor ->
       let num, rest = parse_factor factor in
       Ast.(UnOp (Not, num)), rest
    | Id name::OpenParen::rest -> parse_function_call toks
    | Id name::rest -> Ast.(Var (ID name)), rest
    | Int i::rest -> Ast.(Const (Int i)), rest
    | Char c::rest -> Ast.(Const (Char c)), rest
    | rest -> failwith "Failed to parse factor"

  and parse_term toks = let open Tok in parse_bin_exp parse_factor [Mult; Div; Mod] toks

  and parse_additive_exp toks = let open Tok in parse_bin_exp parse_term [Plus; Minus] toks

  and parse_shift_exp toks = let open Tok in parse_bin_exp parse_additive_exp [ShiftLeft; ShiftRight] toks

  and parse_relational_exp toks = let open Tok in parse_bin_exp parse_shift_exp [Lt; Le; Gt; Ge] toks

  and parse_equality_exp toks = let open Tok in parse_bin_exp parse_relational_exp [DoubleEq; Neq] toks

  and parse_bitwise_and_exp toks = parse_bin_exp parse_equality_exp [Tok.BitAnd] toks

  and parse_xor_exp toks = parse_bin_exp parse_bitwise_and_exp [Tok.Xor] toks

  and parse_bitwise_or_exp toks = parse_bin_exp parse_xor_exp [Tok.BitOr] toks

  and parse_and_exp toks = parse_bin_exp parse_bitwise_or_exp [Tok.And] toks

  and parse_or_exp toks = parse_bin_exp parse_and_exp [Tok.Or] toks

  and parse_ternary_exp toks =
    let exp_1, rest = parse_or_exp toks in
    match rest with
    | Tok.Question::branch1_tokens ->
       let branch1, rest = parse_exp branch1_tokens in
       begin
         match rest with
         | Tok.Colon::branch2_tokens ->
            let branch2, rest = parse_ternary_exp branch2_tokens in
            Ast.TernOp (exp_1, branch1, branch2), rest
         | _ -> failwith "Expected colon after ternary operator"
       end
    | _ -> exp_1, rest

  and parse_exp = function
    | Tok.(Id v::Eq::rest) ->
       (* assignment statement *)
       let var_id = Ast.ID v in
       let exp, rest = parse_exp rest in
       Ast.(Assign (Equals, var_id, exp)), rest
    | tokens -> parse_ternary_exp tokens
  in
  parse_exp toks

let parse_optional_exp next_expected toks =
  if (List.hd toks) = next_expected then
    None, (List.tl toks)
  else
    let e, rest = parse_expression toks in
    if (List.hd rest = next_expected) then
      Some e, (List.tl rest)
    else
      failwith "Didn't get expected token after exp"

let parse_rest_of_declaration var_id var_type storage_class tokens =
     let init, rest =
       match tokens with
       | Tok.Semicolon::_ -> None, tokens
       | Tok.Eq::rest ->
          let exp, rest = parse_expression rest in
          Some exp, rest
       | _ -> failwith "Invalid initial value for variable"
     in
     let declaration = Ast.{
           var_type = var_type;
           var_name = var_id;
           init = init;
           storage_class = storage_class;
                       }
     in
     begin
       match rest with
       | Tok.Semicolon::rest -> declaration, rest
       | _ -> failwith "Expected semicolon after declaration"
     end

let parse_declaration tokens =
  let storage_class, rest = match tokens with
      | Tok.StaticKeyword::rest -> Ast.Static, rest
      | Tok.ExternKeyword::rest -> Ast.Extern, rest
      | _ -> Ast.Nothing, tokens
  in
  match rest with
  | (Tok.IntKeyword::Tok.Id varname::rest) -> parse_rest_of_declaration (Ast.ID varname) Ast.IntType storage_class rest
  | _ -> failwith (Printf.sprintf "Unexpected keyword %s" (Lex.tok_to_string (List.hd rest)))

let parse_function_body toks =
  let parse_return_statement stmt =
    let exp, rest = parse_expression stmt in
    Ast.ReturnVal exp, rest
  in

  let rec parse_block = function
    | Tok.OpenBrace::more_tokens ->
       begin
         let block_items, rest = parse_block_item_list more_tokens in
         match rest with
         | Tok.CloseBrace::rest -> block_items, rest
         | _ -> failwith "Expected closing brace at end of block"
       end
    | _ -> failwith "Expected opening brace at start of block"

  and parse_if_statement  = function
    | Tok.OpenParen::_ as toks ->
       let cond, rest = parse_expression toks in
       let if_body, rest = parse_statement rest in
       let else_body, rest =
         match rest with
         | Tok.ElseKeyword::else_tokens ->
            let else_body, rest = parse_statement else_tokens in
            Some else_body, rest
         | _ -> None, rest in
       let if_statement = Ast.If { cond; if_body; else_body } in
       if_statement, rest
    | _ -> failwith "Expected '(' after 'if'"

  and parse_for_components toks =
    let cond, rest = parse_optional_exp Tok.Semicolon toks in
    let cond = match cond with
      (* C11 6.8.5.3 - An omitted expression-2 is replaced by a nonzero constant *)
      | None -> Ast.Const (Int 1)
      | Some c -> c
    in
    let post, rest = parse_optional_exp Tok.CloseParen rest in
    let body, rest = parse_statement rest in
    cond, post, body, rest

  and parse_for_statement = function
    | Tok.(OpenParen::((IntKeyword::_) as decl_toks)) ->
       (* for loop w/ variable declaration *)
       let init, rest = parse_declaration decl_toks in
       let cond, post, body, rest = parse_for_components rest in
       Ast.ForDecl { init; cond; post; body }, rest
    | Tok.OpenParen::toks ->
       let init, rest = parse_optional_exp Tok.Semicolon toks in
       let cond, post, body, rest = parse_for_components rest in
       Ast.For { init; cond; post; body }, rest
    | _ -> failwith "PANIC: expected open paren at start of for loop"

  and parse_while_statement toks =
    let cond, rest = parse_expression toks in
    let body, rest = parse_statement rest in
    Ast.While { cond; body }, rest

  and parse_do_while_statement toks =
    let body, rest = parse_statement toks in
    match rest with
    | Tok.WhileKeyword::cond_tokens ->
       let cond, rest = parse_expression cond_tokens in
       begin
         match rest with
         | Tok.Semicolon::rest -> Ast.DoWhile { body; cond }, rest
         | _ -> failwith "Expected semicolon after do-while"
       end
    | _ -> failwith "Expected 'while' after body of do-while"

  (* TODO: actually pay attention to types *)
  and parse_statement toks =
    let open Tok in
    match toks with
    | OpenBrace::_ ->
       let block, rest = parse_block toks in
       Block block, rest
    | IfKeyword::tokens -> parse_if_statement tokens
    | ForKeyword::tokens -> parse_for_statement tokens
  | ReturnKeyword::tokens ->
     let statement, rest = parse_return_statement tokens in
     begin
       match rest with
       | Semicolon::rest -> statement, rest
       | _ -> failwith "Expected semicolon after return statement"
     end
  | WhileKeyword::tokens -> parse_while_statement tokens
  | DoKeyword::tokens -> parse_do_while_statement tokens
  | BreakKeyword::Semicolon::rest -> Ast.Break, rest
  | BreakKeyword::_ -> failwith "Expected semicolon after break"
  | ContinueKeyword::Semicolon::rest -> Ast.Continue, rest
  | ContinueKeyword::_ -> failwith "Expected semicolon after continue"
  | _ ->
     let exp, rest = parse_optional_exp Tok.Semicolon toks in
     Ast.Exp exp, rest

  and parse_block_item tokens =
    let is_declaration = match tokens with
      | Tok.StaticKeyword::_ -> true
      | Tok.ExternKeyword::_ -> true
      | Tok.IntKeyword::_ -> true
      | _ -> false
    in
    if is_declaration then
      let decl, rest = parse_declaration tokens in
      Ast.Decl decl, rest
    else
      let stmt, rest = parse_statement tokens in
      Ast.Statement stmt, rest

  and parse_block_item_list tokens =
    if (List.hd tokens) == Tok.CloseBrace
    then [], tokens
    else
      let next_statement, rest = parse_block_item tokens in
      let statements, rest = parse_block_item_list rest in
      next_statement::statements, rest

  in
  parse_block toks

let parse_next_param = function
  | Tok.IntKeyword::(Id name)::rest ->
     Ast.(Param (IntType, ID name)), rest
  | Tok.CharKeyword::(Id name)::rest ->
     Ast.(Param (CharType, ID name)), rest
  | _ -> failwith "Invalid function parameter"

let rec parse_fun_params = function
  | Tok.CloseParen::rest -> [], rest
  | toks ->
     let param, rest = parse_next_param toks in
     let params, rest =
       match rest with
       | Tok.Comma::more_params -> parse_fun_params more_params
       | CloseParen::after_params -> [], after_params
       | _ -> failwith "Invalid list of parameters"
     in param::params, rest

let parse_fun fun_type name storage_class tokens =
  (* we've already parsed everything up to open paren *)
  let params, rest = parse_fun_params tokens in
  let opt_body, rest =
    match rest with
    | Tok.OpenBrace::_ ->
       let body, rest' = parse_function_body rest in
       Some body, rest'
    | Tok.Semicolon::rest' -> None, rest'
    | _ -> failwith "Unexpected token after function declaration"
  in
  let decl = Ast.Function { fun_type; name; storage_class; params; body=opt_body } in
  decl, rest

let parse_top_level tokens =
  let storage_class, after_storage_class =
    match tokens with
      | Tok.StaticKeyword::toks -> Ast.Static, toks
      | Tok.ExternKeyword::toks -> Ast.Extern, toks
      | otherwise -> Ast.Nothing, tokens
  in
  let tl_type, tl_name, after_id =
    match after_storage_class with
      | Tok.(IntKeyword::Id name::rest) -> Ast.(IntType, ID name, rest)
      | Tok.(CharKeyword::Id name::rest) -> Ast.(CharType, ID name, rest)
      | _ -> failwith "Parse error in parse_top_level: bad toplevel name or top"
  in
  let Ast.ID name = tl_name in
  match after_id with
    | Tok.OpenParen::rest -> parse_fun tl_type tl_name storage_class rest
    | other ->
       let decl, rest = parse_rest_of_declaration tl_name tl_type storage_class after_id in
       (Ast.GlobalVar decl, rest)

let rec parse_top_levels = function
  | [] -> [] (* no functions left to parse *)
  | tokens ->
     let tl, rest = parse_top_level tokens in
     let tls = parse_top_levels rest in
     tl::tls

let parse tokens = Ast.Prog (parse_top_levels tokens)

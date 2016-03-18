
/*
  +------------------------------------------------------------------------+
  | Phalcon Framework                                                      |
  +------------------------------------------------------------------------+
  | Copyright (c) 2011-2014 Phalcon Team (http://www.phalconphp.com)       |
  +------------------------------------------------------------------------+
  | This source file is subject to the New BSD License that is bundled     |
  | with this package in the file docs/LICENSE.txt.                        |
  |                                                                        |
  | If you did not receive a copy of the license and are unable to         |
  | obtain it through the world-wide-web, please send an email             |
  | to license@phalconphp.com so we can send you a copy immediately.       |
  +------------------------------------------------------------------------+
  | Authors: Andres Gutierrez <andres@phalconphp.com>                      |
  |          Eduar Carvajal <eduar@phalconphp.com>                         |
  +------------------------------------------------------------------------+
*/

%token_prefix PHVOLT_
%token_type {phvolt_parser_token*}
%token_destructor {
	if ($$) {
		if ($$->free_flag) {
			efree($$->token);
		}
		efree($$);
	}
}
%default_type {zval*}
%default_destructor {
	if (status) {
		// TODO:
	}
	zval_ptr_dtor($$);
	efree($$);
}
%extra_argument {phvolt_parser_status *status}
%name phvolt_

%right OPEN_DELIMITER .
%left COMMA .
%left IN .
%left QUESTION COLON .
%left RANGE .
%left AND OR .
%left IS EQUALS NOTEQUALS LESS GREATER GREATEREQUAL LESSEQUAL IDENTICAL NOTIDENTICAL .
%left DIVIDE TIMES MOD .
%left PLUS MINUS CONCAT .
%right SBRACKET_OPEN .
%left PIPE .
%right NOT .
%left INCR DECR .
%right PARENTHESES_OPEN .
%left DOT .

%include {

#include "php_phalcon.h"
#include "mvc/view/engine/volt/parser.h"
#include "mvc/view/engine/volt/scanner.h"
#include "mvc/view/engine/volt/volt.h"
#include "mvc/view/exception.h"

#include <Zend/zend_smart_str.h>

#include "kernel/main.h"
#include "kernel/memory.h"
#include "kernel/fcall.h"
#include "kernel/exception.h"


static zval *phvolt_ret_literal_zval(int type, phvolt_parser_token *T, phvolt_scanner_state *state)
{
	zval *ret;

	PHALCON_ALLOC_INIT_ZVAL(ret);
	array_init(ret);
	add_assoc_long(ret, "type", type);
	if (T) {
		add_assoc_stringl(ret, "value", T->token, T->token_len);
		efree(T->token);
		efree(T);
	}

	Z_TRY_ADDREF_P(state->active_file);
	add_assoc_zval(ret, "file", state->active_file);
	add_assoc_long(ret, "line", state->active_line);

	return ret;
}

static zval *phvolt_ret_if_statement(zval *expr, zval *true_statements, zval *false_statements, phvolt_scanner_state *state)
{
	zval *ret;

	PHALCON_ALLOC_INIT_ZVAL(ret);
	array_init(ret);
	add_assoc_long(ret, "type", PHVOLT_T_IF);
	add_assoc_zval(ret, "expr", expr);
	efree(expr);

	if (true_statements) {
		add_assoc_zval(ret, "true_statements", true_statements);
		efree(true_statements);
	}
	if (false_statements) {
		add_assoc_zval(ret, "false_statements", false_statements);
		efree(false_statements);
	}

	Z_TRY_ADDREF_P(state->active_file);
	add_assoc_zval(ret, "file", state->active_file);
	add_assoc_long(ret, "line", state->active_line);

	return ret;
}

static zval *phvolt_ret_elseif_statement(zval *expr, phvolt_scanner_state *state)
{
	zval *ret;

	PHALCON_ALLOC_INIT_ZVAL(ret);
	array_init(ret);
	add_assoc_long(ret, "type", PHVOLT_T_ELSEIF);
	add_assoc_zval(ret, "expr", expr);
	efree(expr);

	Z_TRY_ADDREF_P(state->active_file);
	add_assoc_zval(ret, "file", state->active_file);
	add_assoc_long(ret, "line", state->active_line);

	return ret;
}

static zval *phvolt_ret_elsefor_statement(phvolt_scanner_state *state)
{
	zval *ret;

	PHALCON_ALLOC_INIT_ZVAL(ret);
	array_init(ret);
	add_assoc_long(ret, "type", PHVOLT_T_ELSEFOR);

	Z_TRY_ADDREF_P(state->active_file);
	add_assoc_zval(ret, "file", state->active_file);
	add_assoc_long(ret, "line", state->active_line);

	return ret;
}

static zval *phvolt_ret_for_statement(phvolt_parser_token *variable, phvolt_parser_token *key, zval *expr, zval *if_expr, zval *block_statements, phvolt_scanner_state *state)
{
	zval *ret;

	PHALCON_ALLOC_INIT_ZVAL(ret);
	array_init(ret);
	add_assoc_long(ret, "type", PHVOLT_T_FOR);

	add_assoc_stringl(ret, "variable", variable->token, variable->token_len);
	efree(variable->token);
	efree(variable);

	if (key) {
		add_assoc_stringl(ret, "key", key->token, key->token_len);
		efree(key->token);
		efree(key);
	}

	add_assoc_zval(ret, "expr", expr);
	efree(expr);

	if (if_expr) {
		add_assoc_zval(ret, "if_expr", if_expr);
		efree(if_expr);
	}

	add_assoc_zval(ret, "block_statements", block_statements);
	efree(block_statements);

	Z_TRY_ADDREF_P(state->active_file);
	add_assoc_zval(ret, "file", state->active_file);
	add_assoc_long(ret, "line", state->active_line);

	return ret;
}

static zval *phvolt_ret_cache_statement(zval *expr, zval *lifetime, zval *block_statements, phvolt_scanner_state *state)
{
	zval *ret;

	PHALCON_ALLOC_INIT_ZVAL(ret);
	array_init(ret);

	add_assoc_long(ret, "type", PHVOLT_T_CACHE);
	add_assoc_zval(ret, "expr", expr);

	if (lifetime) {
		add_assoc_zval(ret, "lifetime", lifetime);
		efree(lifetime);
	}
	add_assoc_zval(ret, "block_statements", block_statements);
	efree(block_statements);

	Z_TRY_ADDREF_P(state->active_file);
	add_assoc_zval(ret, "file", state->active_file);
	add_assoc_long(ret, "line", state->active_line);

	return ret;
}

static zval *phvolt_ret_set_statement(zval *assignments)
{
	zval *ret;

	PHALCON_ALLOC_INIT_ZVAL(ret);
	array_init_size(ret, 2);
	add_assoc_long(ret, "type", PHVOLT_T_SET);

	add_assoc_zval(ret, "assignments", assignments);
	efree(assignments);

	return ret;
}

static zval *phvolt_ret_set_assignment(phvolt_parser_token *variable, int operator, zval *expr, phvolt_scanner_state *state)
{
	zval *ret;

	PHALCON_ALLOC_INIT_ZVAL(ret);
	array_init_size(ret, 5);

	add_assoc_stringl(ret, "variable", variable->token, variable->token_len);
	efree(variable->token);
	efree(variable);

	add_assoc_long(ret, "op", operator);
	add_assoc_zval(ret, "expr", expr);
	efree(expr);

	Z_TRY_ADDREF_P(state->active_file);
	add_assoc_zval(ret, "file", state->active_file);
	add_assoc_long(ret, "line", state->active_line);

	return ret;
}

static zval *phvolt_ret_echo_statement(zval *expr, phvolt_scanner_state *state)
{
	zval *ret;

	PHALCON_ALLOC_INIT_ZVAL(ret);
	array_init_size(ret, 4);
	add_assoc_long(ret, "type", PHVOLT_T_ECHO);
	add_assoc_zval(ret, "expr", expr);
	efree(expr);

	Z_TRY_ADDREF_P(state->active_file);
	add_assoc_zval(ret, "file", state->active_file);
	add_assoc_long(ret, "line", state->active_line);

	return ret;
}

static zval *phvolt_ret_block_statement(phvolt_parser_token *name, zval *block_statements, phvolt_scanner_state *state)
{
	zval *ret;

	PHALCON_ALLOC_INIT_ZVAL(ret);
	array_init(ret);

	add_assoc_long(ret, "type", PHVOLT_T_BLOCK);

	add_assoc_stringl(ret, "name", name->token, name->token_len);
	efree(name->token);
	efree(name);

	if (block_statements) {
		add_assoc_zval(ret, "block_statements", block_statements);
		efree(block_statements);
	}

	Z_TRY_ADDREF_P(state->active_file);
	add_assoc_zval(ret, "file", state->active_file);
	add_assoc_long(ret, "line", state->active_line);

	return ret;
}

static zval *phvolt_ret_macro_statement(phvolt_parser_token *macro_name, zval *parameters, zval *block_statements, phvolt_scanner_state *state)
{
	zval *ret;

	PHALCON_ALLOC_INIT_ZVAL(ret);
	array_init(ret);
	add_assoc_long(ret, "type", PHVOLT_T_MACRO);

	add_assoc_stringl(ret, "name", macro_name->token, macro_name->token_len);
	efree(macro_name->token);
	efree(macro_name);

	if (parameters) {
		add_assoc_zval(ret, "parameters", parameters);
		efree(parameters);
	}

	if (block_statements) {
		add_assoc_zval(ret, "block_statements", block_statements);
		efree(block_statements);
	}

	Z_TRY_ADDREF_P(state->active_file);
	add_assoc_zval(ret, "file", state->active_file);
	add_assoc_long(ret, "line", state->active_line);

	return ret;
}

static zval *phvolt_ret_macro_parameter(phvolt_parser_token *variable, zval *default_value, phvolt_scanner_state *state)
{
	zval *ret;

	PHALCON_ALLOC_INIT_ZVAL(ret);
	array_init_size(ret, 5);

	add_assoc_stringl(ret, "variable", variable->token, variable->token_len);
	efree(variable->token);
	efree(variable);

	if (default_value) {
		add_assoc_zval(ret, "default", default_value);
		efree(default_value);
	}

	Z_TRY_ADDREF_P(state->active_file);
	add_assoc_zval(ret, "file", state->active_file);
	add_assoc_long(ret, "line", state->active_line);

	return ret;
}

static zval *phvolt_ret_extends_statement(phvolt_parser_token *P, phvolt_scanner_state *state)
{
	zval *ret;

	PHALCON_ALLOC_INIT_ZVAL(ret);
	array_init_size(ret, 4);

	add_assoc_long(ret, "type", PHVOLT_T_EXTENDS);
	add_assoc_stringl(ret, "path", P->token, P->token_len);
	efree(P->token);
	efree(P);

	Z_TRY_ADDREF_P(state->active_file);
	add_assoc_zval(ret, "file", state->active_file);
	add_assoc_long(ret, "line", state->active_line);

	return ret;
}

static zval *phvolt_ret_include_statement(zval *path, zval *params, phvolt_scanner_state *state)
{
	zval *ret;

	PHALCON_ALLOC_INIT_ZVAL(ret);
	array_init_size(ret, 4);

	add_assoc_long(ret, "type", PHVOLT_T_INCLUDE);
	add_assoc_zval(ret, "path", path);
	efree(path);

	if (params) {
		add_assoc_zval(ret, "params", params);
		efree(params);
	}

	Z_TRY_ADDREF_P(state->active_file);
	add_assoc_zval(ret, "file", state->active_file);
	add_assoc_long(ret, "line", state->active_line);

	return ret;
}

static zval *phvolt_ret_do_statement(zval *expr, phvolt_scanner_state *state)
{
	zval *ret;

	PHALCON_ALLOC_INIT_ZVAL(ret);
	array_init_size(ret, 4);
	add_assoc_long(ret, "type", PHVOLT_T_DO);
	add_assoc_zval(ret, "expr", expr);
	efree(expr);

	Z_TRY_ADDREF_P(state->active_file);
	add_assoc_zval(ret, "file", state->active_file);
	add_assoc_long(ret, "line", state->active_line);

	return ret;
}

static zval *phvolt_ret_return_statement(zval *expr, phvolt_scanner_state *state)
{
	zval *ret;

	PHALCON_ALLOC_INIT_ZVAL(ret);
	array_init_size(ret, 4);
	add_assoc_long(ret, "type", PHVOLT_T_RETURN);
	add_assoc_zval(ret, "expr", expr);
	efree(expr);

	Z_TRY_ADDREF_P(state->active_file);
	add_assoc_zval(ret, "file", state->active_file);
	add_assoc_long(ret, "line", state->active_line);

	return ret;
}

static zval *phvolt_ret_autoescape_statement(int enable, zval *block_statements, phvolt_scanner_state *state)
{
	zval *ret;

	PHALCON_ALLOC_INIT_ZVAL(ret);
	array_init_size(ret, 5);

	add_assoc_long(ret, "type", PHVOLT_T_AUTOESCAPE);
	add_assoc_long(ret, "enable", enable);
	add_assoc_zval(ret, "block_statements", block_statements);
	efree(block_statements);

	Z_TRY_ADDREF_P(state->active_file);
	add_assoc_zval(ret, "file", state->active_file);
	add_assoc_long(ret, "line", state->active_line);

	return ret;
}

static zval *phvolt_ret_empty_statement(phvolt_scanner_state *state)
{
	zval *ret;

	PHALCON_ALLOC_INIT_ZVAL(ret);
	array_init_size(ret, 3);
	add_assoc_long(ret, "type", PHVOLT_T_EMPTY_STATEMENT);

	Z_TRY_ADDREF_P(state->active_file);
	add_assoc_zval(ret, "file", state->active_file);
	add_assoc_long(ret, "line", state->active_line);

	return ret;
}

static zval *phvolt_ret_break_statement(phvolt_scanner_state *state)
{
	zval *ret;

	PHALCON_ALLOC_INIT_ZVAL(ret);
	array_init_size(ret, 3);
	add_assoc_long(ret, "type", PHVOLT_T_BREAK);

	Z_TRY_ADDREF_P(state->active_file);
	add_assoc_zval(ret, "file", state->active_file);
	add_assoc_long(ret, "line", state->active_line);

	return ret;
}

static zval *phvolt_ret_continue_statement(phvolt_scanner_state *state)
{
	zval *ret;

	PHALCON_ALLOC_INIT_ZVAL(ret);
	array_init_size(ret, 3);
	add_assoc_long(ret, "type", PHVOLT_T_CONTINUE);

	Z_TRY_ADDREF_P(state->active_file);
	add_assoc_zval(ret, "file", state->active_file);
	add_assoc_long(ret, "line", state->active_line);

	return ret;
}

static zval *phvolt_ret_zval_list(zval *list_left, zval *right_list)
{
	zval *ret, *item;

	PHALCON_ALLOC_ZVAL(ret);
	array_init(ret);

	if (list_left) {
		if (zend_hash_index_exists(Z_ARRVAL_P(list_left), 0)) {
			ZEND_HASH_FOREACH_VAL(Z_ARRVAL_P(list_left), item) {
				add_next_index_zval(ret, item);
			} ZEND_HASH_FOREACH_END();
		} else {
			add_next_index_zval(ret, list_left);
		}
		efree(list_left);
	}

	add_next_index_zval(ret, right_list);
	efree(right_list);

	return ret;
}

static zval *phvolt_ret_named_item(phvolt_parser_token *name, zval *expr, phvolt_scanner_state *state)
{
	zval *ret;

	PHALCON_ALLOC_INIT_ZVAL(ret);
	array_init(ret);
	add_assoc_zval(ret, "expr", expr);
	efree(expr);
	if (name != NULL) {
		add_assoc_stringl(ret, "name", name->token, name->token_len);
		efree(name->token);
		efree(name);
	}

	Z_TRY_ADDREF_P(state->active_file);
	add_assoc_zval(ret, "file", state->active_file);
	add_assoc_long(ret, "line", state->active_line);

	return ret;
}

static zval *phvolt_ret_expr(int type, zval *left, zval *right, zval *ternary, phvolt_scanner_state *state)
{
	zval *ret;

	PHALCON_ALLOC_INIT_ZVAL(ret);
	array_init(ret);
	add_assoc_long(ret, "type", type);

	if (ternary) {
		add_assoc_zval(ret, "ternary", ternary);
		efree(ternary);
	}

	if (left) {
		add_assoc_zval(ret, "left", left);
		efree(left);
	}

	if (right) {
		add_assoc_zval(ret, "right", right);
		efree(right);
	}

	Z_TRY_ADDREF_P(state->active_file);
	add_assoc_zval(ret, "file", state->active_file);
	add_assoc_long(ret, "line", state->active_line);

	return ret;
}

static zval *phvolt_ret_slice(zval *left, zval *start, zval *end, phvolt_scanner_state *state)
{
	zval *ret;

	PHALCON_ALLOC_INIT_ZVAL(ret);
	array_init(ret);
	add_assoc_long(ret, "type", PHVOLT_T_SLICE);
	add_assoc_zval(ret, "left", left);
	efree(left);

	if (start != NULL) {
		add_assoc_zval(ret, "start", start);
		efree(start);
	}

	if (end != NULL) {
		add_assoc_zval(ret, "end", end);
		efree(end);
	}

	Z_TRY_ADDREF_P(state->active_file);
	add_assoc_zval(ret, "file", state->active_file);
	add_assoc_long(ret, "line", state->active_line);

	return ret;
}

static zval *phvolt_ret_func_call(zval *expr, zval *arguments, phvolt_scanner_state *state)
{
	zval *ret;

	PHALCON_ALLOC_INIT_ZVAL(ret);
	array_init(ret);
	add_assoc_long(ret, "type", PHVOLT_T_FCALL);
	add_assoc_zval(ret, "name", expr);
	efree(expr);

	if (arguments) {
		add_assoc_zval(ret, "arguments", arguments);
		efree(arguments);
	}

	Z_TRY_ADDREF_P(state->active_file);
	add_assoc_zval(ret, "file", state->active_file);
	add_assoc_long(ret, "line", state->active_line);

	return ret;
}

static zval *phvolt_ret_macro_call_statement(zval *expr, zval *arguments, zval *caller, phvolt_scanner_state *state)
{
	zval *ret;

	PHALCON_ALLOC_INIT_ZVAL(ret);
	array_init(ret);
	add_assoc_long(ret, "type", PHVOLT_T_CALL);
	add_assoc_zval(ret, "name", expr);
	efree(expr);

	if (arguments) {
		add_assoc_zval(ret, "arguments", arguments);
		efree(arguments);
	}

	if (caller) {
		add_assoc_zval(ret, "caller", caller);
		efree(caller);
	}

	Z_TRY_ADDREF_P(state->active_file);
	add_assoc_zval(ret, "file", state->active_file);
	add_assoc_long(ret, "line", state->active_line);

	return ret;
}

}

%syntax_error {
	{

		smart_str error_str = {0};

		char *token_name = NULL;
		const phvolt_token_names *tokens = phvolt_tokens;
		int token_len = 0;
		uint active_token = status->scanner_state->active_token;

		if (status->scanner_state->start_length) {

			if (active_token) {

				do {
					if (tokens->code == active_token) {
						token_name = tokens->name;
						token_len = tokens->len;
						break;
					}
					++tokens;
				} while (tokens[0].code != 0);

			}

			smart_str_appendl(&error_str, "Syntax error, unexpected token ", sizeof("Syntax error, unexpected token ") - 1);
			if (!token_name) {
				smart_str_appendl(&error_str, "UNKNOWN", sizeof("UNKNOWN") - 1);
			} else {
				smart_str_appendl(&error_str, token_name, token_len);
			}
			if (status->token->value) {
				smart_str_appendc(&error_str, '(');
				smart_str_appendl(&error_str, status->token->value, status->token->len);
				smart_str_appendc(&error_str, ')');
			}
			smart_str_appendl(&error_str, " in ", sizeof(" in ") - 1);
			smart_str_appendl(&error_str, Z_STRVAL_P(status->scanner_state->active_file), Z_STRLEN_P(status->scanner_state->active_file));
			smart_str_appendl(&error_str, " on line ", sizeof(" on line ") - 1);
			{
				char stmp[MAX_LENGTH_OF_LONG + 1];
				int str_len;
				str_len = slprintf(stmp, sizeof(stmp), "%ld", status->scanner_state->active_line);
				smart_str_appendl(&error_str, stmp, str_len);
			}

		} else {

			smart_str_appendl(&error_str, "Syntax error, unexpected EOF in ", sizeof("Syntax error, unexpected EOF in ") - 1);
			smart_str_appendl(&error_str, Z_STRVAL_P(status->scanner_state->active_file), Z_STRLEN_P(status->scanner_state->active_file));

			/* Report unclosed 'if' blocks */
			if ((status->scanner_state->if_level + status->scanner_state->old_if_level) > 0) {
				if ((status->scanner_state->if_level + status->scanner_state->old_if_level) == 1) {
					smart_str_appendl(&error_str, ", there is one 'if' block without close", sizeof(", there is one 'if' block without close") - 1);
				} else {
					smart_str_appendl(&error_str, ", there are ", sizeof(", there are ") - 1);
					{
						char stmp[MAX_LENGTH_OF_LONG + 1];
						int str_len;
						str_len = slprintf(stmp, sizeof(stmp), "%ld", status->scanner_state->if_level + status->scanner_state->old_if_level);
						smart_str_appendl(&error_str, stmp, str_len);
					}
					smart_str_appendl(&error_str, " 'if' blocks without close", sizeof(" 'if' blocks without close") - 1);
				}
			}

			/* Report unclosed 'for' blocks */
			if (status->scanner_state->for_level > 0) {
				if (status->scanner_state->for_level == 1) {
					smart_str_appendl(&error_str, ", there is one 'for' block without close", sizeof(", there is one 'for' block without close") - 1);
				} else {
					smart_str_appendl(&error_str, ", there are ", sizeof(", there are ") - 1);
					{
						char stmp[MAX_LENGTH_OF_LONG + 1];
						int str_len;
						str_len = slprintf(stmp, sizeof(stmp), "%ld", status->scanner_state->if_level);
						smart_str_appendl(&error_str, stmp, str_len);
					}
					smart_str_appendl(&error_str, " 'for' blocks without close", sizeof(" 'for' blocks without close") - 1);
				}
			}
		}

		smart_str_0(&error_str);

		if (error_str.s) {
			status->syntax_error = estrndup(error_str.s->val, error_str.s->len);
			status->syntax_error_len = error_str.s->len;
		} else {
			status->syntax_error = NULL;
		}
		smart_str_free(&error_str);

	}

	status->status = PHVOLT_PARSING_FAILED;
}

program ::= volt_language(Q) . {
	status->ret = Q;
}

volt_language(R) ::= statement_list(L) . {
	R = L;
}

statement_list(R) ::= statement_list(L) statement(S) . {
	R = phvolt_ret_zval_list(L, S);
}

statement_list(R) ::= statement(S) . {
	R = phvolt_ret_zval_list(NULL, S);
}

statement(R) ::= raw_fragment(F) . {
	R = F;
}

statement(R) ::= if_statement(I) . {
	R = I;
}

statement(R) ::= elseif_statement(E) . {
	R = E;
}

statement(R) ::= elsefor_statement(E) . {
	R = E;
}

statement(R) ::= for_statement(E) . {
	R = E;
}

statement(R) ::= set_statement(S) . {
	R = S;
}

statement(R) ::= echo_statement(E) . {
	R = E;
}

statement(R) ::= block_statement(E) . {
	R = E;
}

statement(R) ::= cache_statement(E) . {
	R = E;
}

statement(R) ::= extends_statement(E) . {
	R = E;
}

statement(R) ::= include_statement(E) . {
	R = E;
}

statement(R) ::= do_statement(E) . {
	R = E;
}

statement(R) ::= return_statement(E) . {
	R = E;
}

statement(R) ::= autoescape_statement(E) . {
	R = E;
}

statement(R) ::= break_statement(E) . {
	R = E;
}

statement(R) ::= continue_statement(E) . {
	R = E;
}

statement(R) ::= macro_statement(E) . {
	R = E;
}

statement(R) ::= empty_statement(E) . {
	R = E;
}

statement(R) ::= macro_call_statement(E) . {
	R = E;
}

if_statement(R) ::= OPEN_DELIMITER IF expr(E) CLOSE_DELIMITER statement_list(T) OPEN_DELIMITER ENDIF CLOSE_DELIMITER . {
	R = phvolt_ret_if_statement(E, T, NULL, status->scanner_state);
}

if_statement(R) ::= OPEN_DELIMITER IF expr(E) CLOSE_DELIMITER OPEN_DELIMITER ENDIF CLOSE_DELIMITER . {
	R = phvolt_ret_if_statement(E, NULL, NULL, status->scanner_state);
}

if_statement(R) ::= OPEN_DELIMITER IF expr(E) CLOSE_DELIMITER statement_list(T) OPEN_DELIMITER ELSE CLOSE_DELIMITER statement_list(F) OPEN_DELIMITER ENDIF CLOSE_DELIMITER . {
	R = phvolt_ret_if_statement(E, T, F, status->scanner_state);
}

if_statement(R) ::= OPEN_DELIMITER IF expr(E) CLOSE_DELIMITER statement_list(T) OPEN_DELIMITER ELSE CLOSE_DELIMITER OPEN_DELIMITER ENDIF CLOSE_DELIMITER . {
	R = phvolt_ret_if_statement(E, T, NULL, status->scanner_state);
}

if_statement(R) ::= OPEN_DELIMITER IF expr(E) CLOSE_DELIMITER OPEN_DELIMITER ELSE CLOSE_DELIMITER OPEN_DELIMITER ENDIF CLOSE_DELIMITER . {
	R = phvolt_ret_if_statement(E, NULL, NULL, status->scanner_state);
}

elseif_statement(R) ::= OPEN_DELIMITER ELSEIF expr(E) CLOSE_DELIMITER . {
	R = phvolt_ret_elseif_statement(E, status->scanner_state);
}

elsefor_statement(R) ::= OPEN_DELIMITER ELSEFOR CLOSE_DELIMITER . {
	R = phvolt_ret_elsefor_statement(status->scanner_state);
}

for_statement(R) ::= OPEN_DELIMITER FOR IDENTIFIER(I) IN expr(E) CLOSE_DELIMITER statement_list(T) OPEN_DELIMITER ENDFOR CLOSE_DELIMITER . {
	R = phvolt_ret_for_statement(I, NULL, E, NULL, T, status->scanner_state);
}

for_statement(R) ::= OPEN_DELIMITER FOR IDENTIFIER(I) IN expr(E) IF expr(IE) CLOSE_DELIMITER statement_list(T) OPEN_DELIMITER ENDFOR CLOSE_DELIMITER . {
	R = phvolt_ret_for_statement(I, NULL, E, IE, T, status->scanner_state);
}

for_statement(R) ::= OPEN_DELIMITER FOR IDENTIFIER(K) COMMA IDENTIFIER(V) IN expr(E) CLOSE_DELIMITER statement_list(T) OPEN_DELIMITER ENDFOR CLOSE_DELIMITER . {
	R = phvolt_ret_for_statement(V, K, E, NULL, T, status->scanner_state);
}

for_statement(R) ::= OPEN_DELIMITER FOR IDENTIFIER(K) COMMA IDENTIFIER(V) IN expr(E) IF expr(IE) CLOSE_DELIMITER statement_list(T) OPEN_DELIMITER ENDFOR CLOSE_DELIMITER . {
	R = phvolt_ret_for_statement(V, K, E, IE, T, status->scanner_state);
}

set_statement(R) ::= OPEN_DELIMITER SET set_assignments(L) CLOSE_DELIMITER . {
	R = phvolt_ret_set_statement(L);
}

set_assignments(R) ::= set_assignments(L) COMMA set_assignment(S) . {
	R = phvolt_ret_zval_list(L, S);
}

set_assignments(R) ::= set_assignment(S) . {
	R = phvolt_ret_zval_list(NULL, S);
}

set_assignment(R) ::= IDENTIFIER(I) ASSIGN expr(E) . {
	R = phvolt_ret_set_assignment(I, PHVOLT_T_ASSIGN, E, status->scanner_state);
}

set_assignment(R) ::= IDENTIFIER(I) ADD_ASSIGN expr(E) . {
	R = phvolt_ret_set_assignment(I, PHVOLT_T_ADD_ASSIGN, E, status->scanner_state);
}

set_assignment(R) ::= IDENTIFIER(I) SUB_ASSIGN expr(E) . {
	R = phvolt_ret_set_assignment(I, PHVOLT_T_SUB_ASSIGN, E, status->scanner_state);
}

set_assignment(R) ::= IDENTIFIER(I) MUL_ASSIGN expr(E) . {
	R = phvolt_ret_set_assignment(I, PHVOLT_T_MUL_ASSIGN, E, status->scanner_state);
}

set_assignment(R) ::= IDENTIFIER(I) DIV_ASSIGN expr(E) . {
	R = phvolt_ret_set_assignment(I, PHVOLT_T_DIV_ASSIGN, E, status->scanner_state);
}

macro_statement(R) ::= OPEN_DELIMITER MACRO IDENTIFIER(I) PARENTHESES_OPEN PARENTHESES_CLOSE CLOSE_DELIMITER statement_list(T) OPEN_DELIMITER ENDMACRO CLOSE_DELIMITER . {
	R = phvolt_ret_macro_statement(I, NULL, T, status->scanner_state);
}

macro_statement(R) ::= OPEN_DELIMITER MACRO IDENTIFIER(I) PARENTHESES_OPEN macro_parameters(P) PARENTHESES_CLOSE CLOSE_DELIMITER statement_list(T) OPEN_DELIMITER ENDMACRO CLOSE_DELIMITER . {
	R = phvolt_ret_macro_statement(I, P, T, status->scanner_state);
}

macro_parameters(R) ::= macro_parameters(L) COMMA macro_parameter(I) . {
	R = phvolt_ret_zval_list(L, I);
}

macro_parameters(R) ::= macro_parameter(I) . {
	R = phvolt_ret_zval_list(NULL, I);
}

macro_parameter(R) ::= IDENTIFIER(I) . {
	R = phvolt_ret_macro_parameter(I, NULL, status->scanner_state);
}

macro_parameter(R) ::= IDENTIFIER(I) ASSIGN macro_parameter_default(D) . {
	R = phvolt_ret_macro_parameter(I, D, status->scanner_state);
}

macro_parameter_default(R) ::= INTEGER(I) . {
	R = phvolt_ret_literal_zval(PHVOLT_T_INTEGER, I, status->scanner_state);
}

macro_parameter_default(R) ::= STRING(S) . {
	R = phvolt_ret_literal_zval(PHVOLT_T_STRING, S, status->scanner_state);
}

macro_parameter_default(R) ::= DOUBLE(D) . {
	R = phvolt_ret_literal_zval(PHVOLT_T_DOUBLE, D, status->scanner_state);
}

macro_parameter_default(R) ::= NULL . {
	R = phvolt_ret_literal_zval(PHVOLT_T_NULL, NULL, status->scanner_state);
}

macro_parameter_default(R) ::= FALSE . {
	R = phvolt_ret_literal_zval(PHVOLT_T_FALSE, NULL, status->scanner_state);
}

macro_parameter_default(R) ::= TRUE . {
	R = phvolt_ret_literal_zval(PHVOLT_T_TRUE, NULL, status->scanner_state);
}

macro_call_statement(R) ::= OPEN_DELIMITER CALL expr(E) PARENTHESES_OPEN argument_list(L) PARENTHESES_CLOSE CLOSE_DELIMITER statement_list(C) OPEN_DELIMITER ENDCALL CLOSE_DELIMITER . {
	R = phvolt_ret_macro_call_statement(E, L, C, status->scanner_state);
}

macro_call_statement(R) ::= OPEN_DELIMITER CALL expr(E) PARENTHESES_OPEN PARENTHESES_CLOSE CLOSE_DELIMITER OPEN_DELIMITER ENDCALL CLOSE_DELIMITER . {
	R = phvolt_ret_macro_call_statement(E, NULL, NULL, status->scanner_state);
}

empty_statement(R) ::= OPEN_DELIMITER CLOSE_DELIMITER . {
	R = phvolt_ret_empty_statement(status->scanner_state);
}

echo_statement(R) ::= OPEN_EDELIMITER expr(E) CLOSE_EDELIMITER . {
	R = phvolt_ret_echo_statement(E, status->scanner_state);
}

block_statement(R) ::= OPEN_DELIMITER BLOCK IDENTIFIER(I) CLOSE_DELIMITER statement_list(T) OPEN_DELIMITER ENDBLOCK CLOSE_DELIMITER . {
	R = phvolt_ret_block_statement(I, T, status->scanner_state);
}

block_statement(R) ::= OPEN_DELIMITER BLOCK IDENTIFIER(I) CLOSE_DELIMITER OPEN_DELIMITER ENDBLOCK CLOSE_DELIMITER . {
	R = phvolt_ret_block_statement(I, NULL, status->scanner_state);
}

cache_statement(R) ::= OPEN_DELIMITER CACHE expr(E) CLOSE_DELIMITER statement_list(T) OPEN_DELIMITER ENDCACHE CLOSE_DELIMITER . {
	R = phvolt_ret_cache_statement(E, NULL, T, status->scanner_state);
}

cache_statement(R) ::= OPEN_DELIMITER CACHE expr(E) cache_lifetime(N) CLOSE_DELIMITER statement_list(T) OPEN_DELIMITER ENDCACHE CLOSE_DELIMITER . {
	R = phvolt_ret_cache_statement(E, N, T, status->scanner_state);
}

cache_lifetime(R) ::= INTEGER(I) . {
	R = phvolt_ret_literal_zval(PHVOLT_T_INTEGER, I, status->scanner_state);
}

cache_lifetime(R) ::= IDENTIFIER(I) . {
	R = phvolt_ret_literal_zval(PHVOLT_T_IDENTIFIER, I, status->scanner_state);
}

extends_statement(R) ::= OPEN_DELIMITER EXTENDS STRING(S) CLOSE_DELIMITER . {
	R = phvolt_ret_extends_statement(S, status->scanner_state);
}

include_statement(R) ::= OPEN_DELIMITER INCLUDE expr(E) CLOSE_DELIMITER . {
	R = phvolt_ret_include_statement(E, NULL, status->scanner_state);
}

include_statement(R) ::= OPEN_DELIMITER INCLUDE expr(E) WITH expr(P) CLOSE_DELIMITER . {
	R = phvolt_ret_include_statement(E, P, status->scanner_state);
}

do_statement(R) ::= OPEN_DELIMITER DO expr(E) CLOSE_DELIMITER . {
	R = phvolt_ret_do_statement(E, status->scanner_state);
}

return_statement(R) ::= OPEN_DELIMITER RETURN expr(E) CLOSE_DELIMITER . {
	R = phvolt_ret_return_statement(E, status->scanner_state);
}

autoescape_statement(R) ::= OPEN_DELIMITER AUTOESCAPE FALSE CLOSE_DELIMITER statement_list(T) OPEN_DELIMITER ENDAUTOESCAPE CLOSE_DELIMITER . {
	R = phvolt_ret_autoescape_statement(0, T, status->scanner_state);
}

autoescape_statement(R) ::= OPEN_DELIMITER AUTOESCAPE TRUE CLOSE_DELIMITER statement_list(T) OPEN_DELIMITER ENDAUTOESCAPE CLOSE_DELIMITER . {
	R = phvolt_ret_autoescape_statement(1, T, status->scanner_state);
}

break_statement(R) ::= OPEN_DELIMITER BREAK CLOSE_DELIMITER . {
	R = phvolt_ret_break_statement(status->scanner_state);
}

continue_statement(R) ::= OPEN_DELIMITER CONTINUE CLOSE_DELIMITER . {
	R = phvolt_ret_continue_statement(status->scanner_state);
}

raw_fragment(R) ::= RAW_FRAGMENT(F) . {
	R = phvolt_ret_literal_zval(PHVOLT_T_RAW_FRAGMENT, F, status->scanner_state);
}

expr(R) ::= MINUS expr(E) . {
	R = phvolt_ret_expr(PHVOLT_T_MINUS, NULL, E, NULL, status->scanner_state);
}

expr(R) ::= PLUS expr(E) . {
	R = phvolt_ret_expr(PHVOLT_T_PLUS, NULL, E, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) MINUS expr(O2) . {
	R = phvolt_ret_expr(PHVOLT_T_SUB, O1, O2, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) PLUS expr(O2) . {
	R = phvolt_ret_expr(PHVOLT_T_ADD, O1, O2, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) TIMES expr(O2) . {
	R = phvolt_ret_expr(PHVOLT_T_MUL, O1, O2, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) TIMES TIMES expr(O2) . {
	R = phvolt_ret_expr(PHVOLT_T_POW, O1, O2, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) DIVIDE expr(O2) . {
	R = phvolt_ret_expr(PHVOLT_T_DIV, O1, O2, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) DIVIDE DIVIDE expr(O2) . {
	R = phvolt_ret_expr(PHVOLT_T_MOD, O1, O2, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) MOD expr(O2) . {
	R = phvolt_ret_expr(PHVOLT_T_MOD, O1, O2, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) AND expr(O2) . {
	R = phvolt_ret_expr(PHVOLT_T_AND, O1, O2, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) OR expr(O2) . {
	R = phvolt_ret_expr(PHVOLT_T_OR, O1, O2, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) CONCAT expr(O2) . {
	R = phvolt_ret_expr(PHVOLT_T_CONCAT, O1, O2, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) PIPE expr(O2) . {
	R = phvolt_ret_expr(PHVOLT_T_PIPE, O1, O2, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) RANGE expr(O2) . {
	R = phvolt_ret_expr(PHVOLT_T_RANGE, O1, O2, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) EQUALS expr(O2) . {
	R = phvolt_ret_expr(PHVOLT_T_EQUALS, O1, O2, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) NOTEQUALS DEFINED . {
	R = phvolt_ret_expr(PHVOLT_T_NOT_ISSET, O1, NULL, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) IS DEFINED . {
	R = phvolt_ret_expr(PHVOLT_T_ISSET, O1, NULL, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) NOTEQUALS EMPTY . {
	R = phvolt_ret_expr(PHVOLT_T_NOT_ISEMPTY, O1, NULL, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) IS EMPTY . {
	R = phvolt_ret_expr(PHVOLT_T_ISEMPTY, O1, NULL, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) NOTEQUALS EVEN . {
	R = phvolt_ret_expr(PHVOLT_T_NOT_ISEVEN, O1, NULL, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) IS EVEN . {
	R = phvolt_ret_expr(PHVOLT_T_ISEVEN, O1, NULL, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) NOTEQUALS ODD . {
	R = phvolt_ret_expr(PHVOLT_T_NOT_ISODD, O1, NULL, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) IS ODD . {
	R = phvolt_ret_expr(PHVOLT_T_ISODD, O1, NULL, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) NOTEQUALS NUMERIC . {
	R = phvolt_ret_expr(PHVOLT_T_NOT_ISNUMERIC, O1, NULL, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) IS NUMERIC . {
	R = phvolt_ret_expr(PHVOLT_T_ISNUMERIC, O1, NULL, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) NOTEQUALS SCALAR . {
	R = phvolt_ret_expr(PHVOLT_T_NOT_ISSCALAR, O1, NULL, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) IS SCALAR . {
	R = phvolt_ret_expr(PHVOLT_T_ISSCALAR, O1, NULL, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) NOTEQUALS ITERABLE . {
	R = phvolt_ret_expr(PHVOLT_T_NOT_ISITERABLE, O1, NULL, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) IS ITERABLE . {
	R = phvolt_ret_expr(PHVOLT_T_ISITERABLE, O1, NULL, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) IS expr(O2) . {
	R = phvolt_ret_expr(PHVOLT_T_IS, O1, O2, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) NOTEQUALS expr(O2) . {
	R = phvolt_ret_expr(PHVOLT_T_NOTEQUALS, O1, O2, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) IDENTICAL expr(O2) . {
	R = phvolt_ret_expr(PHVOLT_T_IDENTICAL, O1, O2, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) NOTIDENTICAL expr(O2) . {
	R = phvolt_ret_expr(PHVOLT_T_NOTIDENTICAL, O1, O2, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) LESS expr(O2) . {
	R = phvolt_ret_expr(PHVOLT_T_LESS, O1, O2, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) GREATER expr(O2) . {
	R = phvolt_ret_expr(PHVOLT_T_GREATER, O1, O2, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) GREATEREQUAL expr(O2) . {
	R = phvolt_ret_expr(PHVOLT_T_GREATEREQUAL, O1, O2, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) LESSEQUAL expr(O2) . {
	R = phvolt_ret_expr(PHVOLT_T_LESSEQUAL, O1, O2, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) DOT expr(O2) . {
	R = phvolt_ret_expr(PHVOLT_T_DOT, O1, O2, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) IN expr(O2) . {
	R = phvolt_ret_expr(PHVOLT_T_IN, O1, O2, NULL, status->scanner_state);
}

expr(R) ::= expr(O1) NOT IN expr(O2) . {
	R = phvolt_ret_expr(PHVOLT_T_NOT_IN, O1, O2, NULL, status->scanner_state);
}

expr(R) ::= NOT expr(E) . {
	R = phvolt_ret_expr(PHVOLT_T_NOT, NULL, E, NULL, status->scanner_state);
}

expr(R) ::= expr(E) INCR . {
	R = phvolt_ret_expr(PHVOLT_T_INCR, E, NULL, NULL, status->scanner_state);
}

expr(R) ::= expr(E) DECR . {
	R = phvolt_ret_expr(PHVOLT_T_DECR, E, NULL, NULL, status->scanner_state);
}

expr(R) ::= PARENTHESES_OPEN expr(E) PARENTHESES_CLOSE . {
	R = phvolt_ret_expr(PHVOLT_T_ENCLOSED, E, NULL, NULL, status->scanner_state);
}

expr(R) ::= SBRACKET_OPEN SBRACKET_CLOSE . {
	R = phvolt_ret_expr(PHVOLT_T_ARRAY, NULL, NULL, NULL, status->scanner_state);
}

expr(R) ::= SBRACKET_OPEN array_list(A) SBRACKET_CLOSE . {
	R = phvolt_ret_expr(PHVOLT_T_ARRAY, A, NULL, NULL, status->scanner_state);
}

expr(R) ::= CBRACKET_OPEN CBRACKET_CLOSE . {
	R = phvolt_ret_expr(PHVOLT_T_ARRAY, NULL, NULL, NULL, status->scanner_state);
}

expr(R) ::= CBRACKET_OPEN array_list(A) CBRACKET_CLOSE . {
	R = phvolt_ret_expr(PHVOLT_T_ARRAY, A, NULL, NULL, status->scanner_state);
}

expr(R) ::= expr(E) SBRACKET_OPEN expr(D) SBRACKET_CLOSE . {
	R = phvolt_ret_expr(PHVOLT_T_ARRAYACCESS, E, D, NULL, status->scanner_state);
}

expr(R) ::= expr(E) QUESTION expr(O1) COLON expr(O2) . {
	R = phvolt_ret_expr(PHVOLT_T_TERNARY, O1, O2, E, status->scanner_state);
}

expr(R) ::= expr(E) SBRACKET_OPEN COLON slice_offset(N) SBRACKET_CLOSE . {
	R = phvolt_ret_slice(E, NULL, N, status->scanner_state);
}

expr(R) ::= expr(E) SBRACKET_OPEN slice_offset(S) COLON SBRACKET_CLOSE . {
	R = phvolt_ret_slice(E, S, NULL, status->scanner_state);
}

expr(R) ::= expr(E) SBRACKET_OPEN slice_offset(S) COLON slice_offset(N) SBRACKET_CLOSE . {
	R = phvolt_ret_slice(E, S, N, status->scanner_state);
}

slice_offset(R) ::= INTEGER(I) . {
	R = phvolt_ret_literal_zval(PHVOLT_T_INTEGER, I, status->scanner_state);
}

slice_offset(R) ::= IDENTIFIER(I) . {
	R = phvolt_ret_literal_zval(PHVOLT_T_IDENTIFIER, I, status->scanner_state);
}

array_list(R) ::= array_list(L) COMMA array_item(I) . {
	R = phvolt_ret_zval_list(L, I);
}

array_list(R) ::= array_item(I) . {
	R = phvolt_ret_zval_list(NULL, I);
}

array_item(R) ::= STRING(S) COLON expr(E) . {
	R = phvolt_ret_named_item(S, E, status->scanner_state);
}

array_item(R) ::= expr(E) . {
	R = phvolt_ret_named_item(NULL, E, status->scanner_state);
}

expr(R) ::= function_call(F) . {
	R = F;
}

function_call(R) ::= expr(E) PARENTHESES_OPEN argument_list(L) PARENTHESES_CLOSE . {
	R = phvolt_ret_func_call(E, L, status->scanner_state);
}

function_call(R) ::= expr(E) PARENTHESES_OPEN PARENTHESES_CLOSE . {
	R = phvolt_ret_func_call(E, NULL, status->scanner_state);
}

argument_list(R) ::= argument_list(L) COMMA argument_item(I) . {
	R = phvolt_ret_zval_list(L, I);
}

argument_list(R) ::= argument_item(I) . {
	R = phvolt_ret_zval_list(NULL, I);
}

argument_item(R) ::= expr(E) . {
	R = phvolt_ret_named_item(NULL, E, status->scanner_state);
}

argument_item(R) ::= STRING(S) COLON expr(E) . {
	R = phvolt_ret_named_item(S, E, status->scanner_state);
}

expr(R) ::= IDENTIFIER(I) . {
	R = phvolt_ret_literal_zval(PHVOLT_T_IDENTIFIER, I, status->scanner_state);
}

expr(R) ::= INTEGER(I) . {
	R = phvolt_ret_literal_zval(PHVOLT_T_INTEGER, I, status->scanner_state);
}

expr(R) ::= STRING(S) . {
	R = phvolt_ret_literal_zval(PHVOLT_T_STRING, S, status->scanner_state);
}

expr(R) ::= DOUBLE(D) . {
	R = phvolt_ret_literal_zval(PHVOLT_T_DOUBLE, D, status->scanner_state);
}

expr(R) ::= NULL . {
	R = phvolt_ret_literal_zval(PHVOLT_T_NULL, NULL, status->scanner_state);
}

expr(R) ::= FALSE . {
	R = phvolt_ret_literal_zval(PHVOLT_T_FALSE, NULL, status->scanner_state);
}

expr(R) ::= TRUE . {
	R = phvolt_ret_literal_zval(PHVOLT_T_TRUE, NULL, status->scanner_state);
}

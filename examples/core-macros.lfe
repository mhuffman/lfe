;; Copyright (c) 2008-2010 Robert Virding. All rights reserved.

;; Redistribution and use in source and binary forms, with or without
;; modification, are permitted provided that the following conditions
;; are met:

;; 1. Redistributions of source code must retain the above copyright
;;    notice, this list of conditions and the following disclaimer.
;; 2. Redistributions in binary form must reproduce the above copyright
;;    notice, this list of conditions and the following disclaimer in the
;;    documentation and/or other materials provided with the distribution.

;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
;; "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
;; LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
;; FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
;; COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
;; INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
;; BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
;; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
;; CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
;; LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
;; ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
;; POSSIBILITY OF SUCH DAMAGE.

;; File    : core-macros.lfe
;; Author  : Robert Virding
;; Purpose : Some of LFE core macrosas they could have been implemented in LFE.

;; This file contains some of the core LFE macros as they could have
;; been implemented in LFE. They are implemented in lfe_macro.erl
;; today as there is yet no way to compile macros, and to ensure that
;; they are always available. These are shown mostly without comments.
;;
;; For some macros we give two versions, an all-in-one version and a
;; recursive more syntax pattern based expansion. This to show
;; different styles of doing the same thing.

(defmacro caar (x) `(car (car ,x)))
(defmacro cadr (x) `(car (cdr ,x)))
(defmacro cdar (x) `(cdr (car ,x)))
(defmacro cddr (x) `(cdr (cdr ,x)))

(defmacro ++
  ;; Cases with quoted lists.
  ((cons (list 'quote (cons a as)) es) `(cons ',a (++ ',as . ,es)))
  ((cons (list 'quote ()) es) `(++ . ,es))
  ;; Cases with explicit cons/list/list*.
  ((cons (list 'list* a) es) `(++ ,a . ,es))
  ((cons (cons 'list* (cons a as)) es) `(cons ,a (++ (list* . ,as) . ,es)))
  ((cons (cons 'list (cons a as)) es) `(cons ,a (++ (list . ,as) . ,es)))
  ((cons (list 'list) es) `(++ . ,es))
  ((cons (list 'cons h t) es) `(cons ,h (++ ,t . ,es)))
  ((cons () es) `(++ . ,es))
  ;; Default cases with unquoted arg.
  ((list e) e)
  ((cons e es) `(call 'erlang '++ ,e (++ . ,es)))
  (() ()))

(defmacro :
  ((list* m f as) `(call ',m ',f . ,as)))

(defmacro ?
  ((list to default)
   `(receive (omega omega) (after ,to ,default)))
  ((list to) `(? ,to (exit 'timeout)))
  (() `(receive (omega omega))))

(defmacro list*
  ((list e) e)
  ((cons e es) `(cons ,e (list* . ,es)))
  (() ()))

;; (defmacro let*
;;   ((cons vbs b)
;;    (: lists foldr
;;      (lambda (vb rest) `(let (,vb) ,rest)) `(progn . ,b) vbs)))

(defmacro let*
  ((cons (cons vb vbs) b) `(let (,vb) (let* ,vbs . ,b)))
  ((cons () b) `(progn . ,b))
  ((cons vb b) `(let ,vb . b)))		;Pass error to let

(defmacro flet*
  ((cons (cons fb fbs) b) `(flet (,fb) (flet* ,fbs . ,b)))
  ((cons () b) `(progn . ,b))
  ((cons fb b) `(flet ,fb . b)))		;Pass error to flet

(defmacro cond
  ((list (cons 'else b)) `(progn . ,b))
  ((cons (cons (list '?= p e) b) cond)
   `(case ,e (,p . ,b) (_ (cond . ,cond))))
  ((cons (cons (list '?= p (= (cons 'when _) g) e) b) cond)
   `(case ,e (,p ,g . ,b) (_ (cond . ,cond))))
  ((cons (cons test b) cond) `(if ,test (progn . ,b) (cond . ,cond)))
  (() `'false))

(defmacro andalso
  ((list e) e)
  ((cons e es) `(if ,e (andalso . ,es) 'false))
  (() `'true))

(defmacro orelse args			;Using single argument
  (case args
    ((list e) e)
    ((cons e es) `(if ,e 'true (orelse . ,es)))
    (() `'false)))

;; This version of backquote is almost an exact copy of a quasiquote
;; expander for Scheme by Andr� van Tonder. It is very compact and
;; with some cons/append optimisations we have added produces quite
;; reasonable code.

(defmacro backquote (e) (bq-expand e 0))

(eval-when-compile
  (defun bq-expand (exp n)
    ;; Note that we cannot *use* backquote or any macros using
    ;; backquote in here! It will cause us to loop.
    (fletrec ((bq-app			;Optimise append
	       ([(list '++ l) r] (bq-app l r)) ;Catch single unquote-splice
	       ([() r] r)
	       ([l ()] l)
	       ([(list 'list l) (cons 'list r)] (cons 'list (cons l r)))
	       ([(list 'list l) r] (list 'cons l r))
	       ([l r] (list '++ l r)))
	      (bq-cons			;Optimise cons
	       ([(list 'quote l) (list 'quote r)] (list 'quote (cons l r)))
	       ([l (cons 'list r)] (cons 'list (cons l r)))
	       ([l ()] (list 'list l))
	       ([l r] (list 'cons l r))))
      (case exp
	((list 'backquote x)	;`(list 'backquote ,(bq-expand x (+ n 1)))
	 (list 'list (list 'quote 'backquote) (bq-expand x (+ n 1))))
	((list 'unquote x) (when (> n 0))
	 (bq-cons 'unquote (bq-expand x (- n 1))))
	((list 'unquote x) (when (=:= n 0)) x)
	((list 'unquote-splicing . x) (when (> n 0))
	 (bq-cons (list 'quote 'unquote-splicing) (bq-expand x (- n 1))))
	;; The next two cases handle splicing into a list.
	(((list 'unquote . x) . y) (when (=:= n 0))
	 (bq-app (cons 'list x) (bq-expand y 0)))
	(((list 'unquote-splicing . x) . y) (when (=:= n 0))
	 (bq-app (cons '++ x) (bq-expand y 0)))
	((cons x y)			;The general list case
	 (bq-cons (bq-expand x n) (bq-expand y n)))
	(_ (when (is_tuple exp))
	   ;; Tuples need some smartness for efficient code to handle
	   ;; when no splicing so as to avoid list_to_tuple.
	   (case (bq-expand (tuple_to_list exp) n)
	     (('list . es) (cons tuple es))
	     ((= ('cons . _) e) (list 'list_to_tuple e))))
	(_ (when (is_atom exp)) (list 'quote exp))
	(_ exp))			;Self quoting
      )))

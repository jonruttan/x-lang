; model.x -- models fitted to data, as values.
;
; A model is a value made by a constructor of the Model class: (Model
; linear) is the linear model.  It holds what is to be fitted and no data.
;
;   (m fit x y)   answers a Fit, the model fitted to the predictors x and
;                 the response y, and leaves m as it was
;
; x has a row for each observation and a column for each predictor: a
; Matrix, a rank-2 Tensor or a list of rows.  A rank-1 Tensor or a flat
; list is one predictor.  y has an element for each observation.  A Fit
; answers:
;
;   coefficients    the slope for each predictor
;   intercept       the constant term
;   fitted          the model's value at each observation
;   residuals       the response less the fitted values
;   determination   the share of the response's variation the model
;                   accounts for
;   predict         the model's value at new rows
;
; Model and Fit are the base classes.  A model is a subclass of Model that
; supplies its fit, and its fitted value a subclass of Fit.  The
; subclasses are reached through the constructors and are not provided.
;
; The linear model is fitted by least squares on the Orthogonal
; factorization of the predictors, with a column of 1s before them for
; the intercept.
;
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module x/num/model)
(import x/type/class)
(import x/type/list)
(import x/num/float float-of f-sub f-div)
(import x/num/tensor)
(import x/num/matrix)

(def %zero (float-of 0))
(def %one (float-of 1))

; X as a list of rows, each a list: a flat list or a rank-1 Tensor is one
; predictor, a row for each element.
(def %rows
  (fn (_ x)
    (let ((rows (if (if (pair? x) #t (null? x)) x (x ->list))))
      (if (if (pair? rows) (pair? (first rows)) #f)
        rows
        (List map (fn (_ e) (list e)) rows)))))

; Y as a rank-1 f64 Tensor.
(def %response
  (fn (_ y)
    (Tensor from (if (if (pair? y) #t (null? y)) y (y ->list)) (lit f64))))

; The rows as an f64 Matrix, with a 1 before each row when CONSTANT.
(def %design
  (fn (_ rows constant)
    (Matrix from (if constant (List map (fn (_ row) (pair 1 row)) rows) rows) (lit f64))))

; The sum of the squares of the elements of T.
(def %sum-squares (fn (_ t) ((t mul t) sum)))

(def-class Fit ()
  (doc "A model fitted to data, from (m fit x y): it answers what the fit found and the model's value at new rows. It holds no reference to the model, which fit leaves unchanged."
    (note "Fit holds what every fitted model shares; each model's fit answers a value of a subclass.")
    (example "(((Model linear) fit '(1 2 3) '(3 5 7)) intercept)" "1.0")
    (see coefficients) (see intercept) (see fitted) (see residuals) (see determination) (see predict))

  (method coefficients (self)
    (doc "The slope for each predictor, in the order of x's columns: the change in the response for a change of 1 in that predictor, the others held."
      (returns Tensor "A rank-1 f64 Tensor, an element for each predictor")
      (example "((((Model linear) fit '((1 0) (0 1) (1 1) (2 1)) '(3 4 6 8)) coefficients) ->list)" "(2.0 3.0)"))
    (Err raise (lit value) "Fit coefficients: this fit supplies none" self))

  (method intercept (self)
    (doc "The constant term: the model's value where every predictor is 0. It is 0 for a model fitted through the origin."
      (returns FLOAT "The intercept")
      (example "(((Model linear) fit '((1 0) (0 1) (1 1) (2 1)) '(3 4 6 8)) intercept)" "1.0"))
    (Err raise (lit value) "Fit intercept: this fit supplies none" self))

  (method fitted (self)
    (doc "The model's value at each observation it was fitted to."
      (known-as "fitted values")
      (returns Tensor "A rank-1 f64 Tensor, an element for each observation")
      (example "((((Model linear) fit '(1 2 3) '(3 5 7)) fitted) ->list)" "(3.0 5.0 7.0)"))
    (Err raise (lit value) "Fit fitted: this fit supplies none" self))

  (method residuals (self)
    (doc "The response less the fitted value, at each observation."
      (returns Tensor "A rank-1 f64 Tensor, an element for each observation")
      (example "((((Model linear) fit '(0 1 2) '(0 0 3)) residuals) ->list)" "(0.5 -1.0 0.5)"))
    (Err raise (lit value) "Fit residuals: this fit supplies none" self))

  (method determination (self)
    (doc "The coefficient of determination: the share of the response's variation the model accounts for, 1 less the residuals' sum of squares over the response's. The response's is taken about its mean, or about 0 for a model fitted through the origin. 1 is a fit through every observation."
      (known-as "R-squared" "r2" "coefficient of determination")
      (returns FLOAT "The share, at most 1; not a number where the response does not vary")
      (example "(((Model linear) fit '(0 1 2) '(0 0 3)) determination)" "0.75"))
    (Err raise (lit value) "Fit determination: this fit supplies none" self))

  (method predict (self (param x Tensor|LIST "New rows, a column for each predictor, as fit takes them"))
    (doc "The model's value at each row of x."
      (returns Tensor "A rank-1 f64 Tensor, an element for each row")
      (example "((((Model linear) fit '(1 2 3) '(3 5 7)) predict '(10 20)) ->list)" "(21.0 41.0)"))
    (Err raise (lit value) "Fit predict: this fit supplies none" self)))

; A fitted linear model.
(def-class LinearFit (extends Fit)
  coefficients    ; a rank-1 f64 Tensor, an element for each predictor
  intercept       ; a Float, 0 through the origin
  fitted          ; a rank-1 f64 Tensor, an element for each observation
  residuals       ; a rank-1 f64 Tensor, the response less fitted
  determination   ; a Float

  (method coefficients (self) (field (lit coefficients)))
  (method intercept (self) (field (lit intercept)))
  (method fitted (self) (field (lit fitted)))
  (method residuals (self) (field (lit residuals)))
  (method determination (self) (field (lit determination)))
  (method predict (self x)
    (let ((slopes (field (lit coefficients))) (m (%design (%rows x) #f)))
      (if (= (List ref 1 (m extent)) (slopes size)) ()
        (Err raise (lit value) "Fit predict: x must have a column for each predictor" (m extent)))
      ((m product slopes) add (field (lit intercept))))))

(def-class Model ()
  (doc "A model to fit to data, as a value. A constructor makes one, and (m fit x y) answers a Fit, leaving the model unchanged, so one model fits many sets of data."
    (note "Model holds what every model shares; each constructor answers a value of a subclass that supplies its own fit.")
    (example "((((Model linear) fit '(1 2 3) '(3 5 7)) coefficients) ->list)" "(2.0)")
    (see linear) (see fit))

  (static
    (method linear (self . (param through SYMBOL "Optional: 'origin fits no intercept"))
      (doc "The linear model: the response as an intercept and a slope for each predictor, fitted by least squares, the coefficients that make the residuals' sum of squares least. With 'origin it has no intercept, a line or plane through the origin."
        (known-as "lm" "linear regression" "ordinary least squares" "OLS")
        (returns Model "The model")
        (example "(((Model linear) fit '(1 2 3) '(3 5 7)) intercept)" "1.0")
        (example "((((Model linear 'origin) fit '(1 2 3) '(2 4 6)) coefficients) ->list)" "(2.0)"))
      (if (if (null? through) #t (eq? (first through) (lit origin))) ()
        (Err raise (lit value) "Model linear: the only option is 'origin" (first through)))
      (new-from Linear (list (lit constant) (null? through)))))

  (method fit (self (param x Tensor|LIST "The predictors: a row for each observation and a column for each predictor, or one predictor as a rank-1 Tensor or a flat list")
                    (param y Tensor|LIST "The response: an element for each observation"))
    (doc "The model fitted to the predictors x and the response y. The model is unchanged."
      (returns Fit "The fitted value")
      (example "(let ((m (Model linear))) (list ((m fit '(1 2 3) '(3 5 7)) intercept) ((m fit '(1 2 3) '(0 1 2)) intercept)))" "(1.0 -1.0)"))
    (Err raise (lit value) "Model fit: this model supplies none" self)))

; The linear model.
(def-class Linear (extends Model)
  constant   ; #t where an intercept is fitted

  (method fit (self x y)
    (let ((constant (field (lit constant))) (rows (%rows x)) (y (%response y)))
      (if (= (List length rows) (y size)) ()
        (Err raise (lit value) "Model fit: x must have a row for each element of y" (list (List length rows) (y size))))
      (let ((design (%design rows constant)))
        (let ((found ((design factor-orthogonal) solve y)))
          (let ((fitted (design product found)))
            (let ((residuals (y sub fitted))
                  (about (if constant (y sub (y mean)) y)))
              (new-from LinearFit
                (list (lit coefficients) (if constant ((found slice 0 1 (found size)) copy) found)
                      (lit intercept) (if constant (found ref 0) %zero)
                      (lit fitted) fitted
                      (lit residuals) residuals
                      (lit determination)
                      (f-sub %one (f-div (%sum-squares residuals) (%sum-squares about))))))))))))

(doc (provide x/num/model Model Fit)
  "Models fitted to data, as values: the Model class makes the linear model, and (m fit x y) answers a Fit holding its coefficients, intercept, fitted values, residuals and coefficient of determination, which predicts at new rows."
  (example "(((Model linear) fit '(1 2 3) '(3 5 7)) intercept)" "1.0"))

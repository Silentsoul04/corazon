#!/usr/bin/python
# -*- coding: utf-8 -*- 

"""
Written by  : pennyw1s3 - github.com/pennyw1s3n
Description : Uses Pythons eval() function
              as a way to implement calculator.
             
Functions available are:
--------------------------------------------
                         + : addition
                         - : subtraction
                         * : multiplication
                         / : division
                         % : percentage
                         e : 2.718281...
                        pi : 3.141592... 
                      sine : sin(rad)
                    cosine : cos(rad)
                   tangent : tan(rad)
                 remainder : XmodY
               square root : sqrt(n)
  round to nearest integer : round(n)
convert degrees to radians : rad(deg)
"""

import math
import sys
import os


def calc(term):
    # This part is for reading and converting arithmetic terms.
    term = term.replace(' ', '')
    term = term.replace('^', '**')
    term = term.replace('=', '')
    term = term.replace('?', '')
    term = term.replace('%', '/100')
    term = term.replace('rad', 'radians')
    term = term.replace('mod', '%')

    functions = ['sin', 'cos', 'tan', 'cosh', 'sinh', 'tanh', 'sqrt', 'pi', 'radians', 'e'] 

    # This part is for reading and converting function expressions.
    term = term.lower()
    
    for function in functions:            
        if function in term:
            withmath = 'math.' + function
            term = term.replace(function, withmath)

    try:

        # here goes the actual evaluating.
        term = eval(term)

    # here goes to the error cases.
    except ZeroDivisionError:

        print("Can't divide by 0.  Please try again.")

    except NameError:

        print('Invalid input.  Please try again')

    except AttributeError:

        print('Please check usage method and try again.')
        
    return term


def result(term):
    """
        input:  term of type str
        output: none
        purpose: passes the argument to the function calc(...) and 
                prints the result onto console.
    """
    print("\n" + str(calc(term)))


def main():
    """
        main-program
        purpose: handles user input and prints 
                 information to the console.
    """
    os.system('clear')
    print """
   _|_|_|            _|                      _|              _|                          
 _|          _|_|_|  _|    _|_|_|  _|    _|  _|    _|_|_|  _|_|_|_|    _|_|    _|  _|_|  
 _|        _|    _|  _|  _|        _|    _|  _|  _|    _|    _|      _|    _|  _|_|      
 _|        _|    _|  _|  _|        _|    _|  _|  _|    _|    _|      _|    _|  _|        
   _|_|_|    _|_|_|  _|    _|_|_|    _|_|_|  _|    _|_|_|      _|_|    _|_|    _|        
                                                                              
Author: pennyw1s3
contac: 083871259489
Janganlupa Bahagia :)
		Contohnya: sin(rad(90)) + 50% * (sqrt(16)) + round(1.42^2)
						Type quit to exit
"""

    if sys.version_info.major >= 3:
        while True:
            k = input("\nInput your command: ")
            if k == 'quit':
                break
            result(k)

    else:
        while True:
            k = raw_input("\nInput your command: ")
            if k == 'quit':
                break
            result(k)


if __name__ == '__main__':
    main()

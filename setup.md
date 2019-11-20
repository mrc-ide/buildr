We'll adopt the convention that the port will be 87 followed by the
R version 2 digit number (so 8730, 8731, etc).

We require a python installation for the web server, currently python 2.

* Install python from [the homepage](https://www.python.org/downloads/windows)
* Add python [to the windows path](https://geek-university.com/python/add-python-to-the-windows-path/), e.g., using `c:\Python27` - do this at the *front* of the system path, not the user path. Add `c:\Python27\scripts` to use pip too because python packaging is fractally awful.
* pip install flask

From the wikipedia port number page this seems like a reasonable
group to use.

* Download R from https://cran.r-project.org/bin/windows/base
* Install following the defaults (it can be useful to make a desktop shortcut though and that is no longer the default)
* Install packages by opening a new R session and running `install.packages(c("R6", "httr", "jsonlite"))`

In separate cmd windows run:

    cd build

And one of

3.2:

    "C:\Program Files\R\R-3.2.5\bin\R" CMD INSTALL q:\buildr
    Q:\buildr\inst\run.py --R "C:\Program Files\R\R-3.2.5\bin" --root 3.2.1 --expose --port 8732

3.3:

    "C:\Program Files\R\R-3.3.1\bin\R" CMD INSTALL q:\buildr
    Q:\buildr\inst\run.py --R "C:\Program Files\R\R-3.3.1\bin" --root 3.3.1 --expose --port 8733

3.4:

    "C:\Program Files\R\R-3.4.4\bin\R" CMD INSTALL q:\buildr
    Q:\buildr\inst\run.py --R "C:\Program Files\R\R-3.4.4\bin" --root 3.4.4 --expose --port 8734

3.5:

    "C:\Program Files\R\R-3.5.3\bin\R" CMD INSTALL q:\buildr
    Q:\buildr\inst\run.py --R "C:\Program Files\R\R-3.5.3\bin" --root 3.5.3 --expose --port 8735

3.6:

    "C:\Program Files\R\R-3.6.1\bin\R" CMD INSTALL q:\buildr
    Q:\buildr\inst\run.py --R "C:\Program Files\R\R-3.6.1\bin" --root 3.6.1 --expose --port 8736

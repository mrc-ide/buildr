We'll adopt the convention that the port will be 87 followed by the
R version 2 digit number (so 8730, 8731, etc).

From the wikipedia port number page this seems like a reasonable
group to use.

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

    "C:\Program Files\R\R-3.4.0\bin\R" CMD INSTALL q:\buildr
    Q:\buildr\inst\run.py --R "C:\Program Files\R\R-3.4.0\bin" --root 3.4.0 --expose --port 8734

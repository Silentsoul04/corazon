#!/bin/bash

echo "masukkan angka pertama"
read p
echo "masukkan angka kedua"
read q
tambah=$(echo "$p + $q" | bc)
echo "hasil penambahan = $tambah"


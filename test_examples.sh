for i in examples/*/*.c
do
    gcc -w -m32 $i             #compile with gcc
    ./a.out                 #run it
    expected=$?             #get exit code
    ./c_comp $i              #compile with c_comp
    base="${i%.*}"
    $base                  #run the thing we assembled
    actual=$?                #get exit code
    echo -n "$i:    "
    if [ "$expected" -ne "$actual" ]
    then
        echo "FAIL"
    else
        echo "OK"
    fi
    rm $base
done

#cleanup
rm a.out

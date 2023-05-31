# XHP Token

* Para la wallets con vestings:

* 1) Definir la fecha en la que empezara el vesting, y ejecutar la función "setStartVestingTime". IMPORTANTE: solo se puede setear 1 vez.

* 2) Ejecutar la función "setVestedWallet" con los siguientes parametros:
    - account: wallet a vestear
    - amount: monto total a vestear (expresado en wei).
    - vestingTime: tiempo del vesting, expresado en meses. (Opciones: 3, 12 y 24).
    - sixMontLock: booleano que representa si el deposito tiene 6 meses de full lock.

* 3) Transferir los fondos correspondientes a las wallets con vestings.

* IMPORTANTE: como medida de seguridad, solo se podrá setear una vez el valor para la variable "startVestingDate". Con esto nos aseguramos que no se pueda modificar, eliminando así la posibilidad de ir modificando la fecha y generar un vesting eterno.
De la misma manera, no se permite generar vestings a wallets que ya tengan saldo.
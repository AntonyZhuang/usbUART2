import serial
while(1):
    try:
        #打开串口
        ser = serial.Serial("COM3",115200,timeout=0.5)
        print("打开串口",ser)

        #向串口写入数据
        data = input("输入发送的数据:")
        ser.write(data.encode('gbk'))
        #接受数据
        receive_data = ser.readline()
        receive = receive_data.decode('gbk')
        print("接收到的数据为:",receive)
        ser.close()#关闭串口
    except Exception as e:
        print("打开串口失败！\n",e)

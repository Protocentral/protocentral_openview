//////////////////////////////////////////////////////////////////////////////////////////
//
//   Desktop GUI for use with ProtoCentral breakout boards and shields
//
//   Writen by: Ashwin Whitchurch (support@protocentral.com)
//   Copyright (c) 2016-2020 ProtoCentral Electronics
//
//   GitHub: https://github.com/Protocentral/protocentral_openview.git
//
//   This software is licensed under the MIT License(http://opensource.org/licenses/MIT). 
//   
//   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT 
//   NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. 
//   IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, 
//   WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE 
//   SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//
/////////////////////////////////////////////////////////////////////////////////////////

import processing.serial.*;                  // Serial Library
import grafica.*;

// Java Swing Package For prompting message
import java.awt.*;
import javax.swing.*;
import static javax.swing.JOptionPane.*;

// File Packages to record the data into a text file
import javax.swing.JFileChooser;
import java.io.FileWriter;
import java.io.BufferedWriter;

// Date Format
import java.util.*;
import java.text.DateFormat;
import java.text.SimpleDateFormat;

// General Java Package
import java.math.*;
import controlP5.*;

import brainflow.DataFilter;
import brainflow.FilterTypes;
import brainflow.NoiseTypes;

import brainflow.BoardIds;
import brainflow.BoardShim;
import brainflow.BrainFlowInputParams;

import brainflow.BrainFlowError;

ControlP5 cp5;

/************** Packet Validation  **********************/
private static final int CESState_Init = 0;
private static final int CESState_SOF1_Found = 1;
private static final int CESState_SOF2_Found = 2;
private static final int CESState_PktLen_Found = 3;

/*CES CMD IF Packet Format*/
private static final int CES_CMDIF_PKT_START_1 = 0x0A;
private static final int CES_CMDIF_PKT_START_2 = 0xFA;
private static final int CES_CMDIF_PKT_STOP = 0x0B;

/*CES CMD IF Packet Indices*/
private static final int CES_CMDIF_IND_LEN = 2;
private static final int CES_CMDIF_IND_LEN_MSB = 3;
private static final int CES_CMDIF_IND_PKTTYPE = 4;
private static int CES_CMDIF_PKT_OVERHEAD = 5;

/************** Packet Related Variables **********************/

int pc_rx_state = 0;                                        // To check the state of the packet
int CES_Pkt_Len;                                             // To store the Packet Length Deatils
int CES_Pkt_Pos_Counter, CES_Data_Counter;                   // Packet and data counter

int CES_Pkt_PktType;         // To store the Packet Type
char CES_Pkt_Data_Counter[] = new char[1000];                

char ces_pkt_ch1_buffer[] = new char[4];                    
char ces_pkt_ch2_buffer[] = new char[4];                   
char ces_pkt_ch3_buffer[] = new char[4];               

char ces_pkt_cv1_buffer[] = new char[4];
char ces_pkt_cv2_buffer[] = new char[4];

int windowSize = 6*128;                                            // Total Size of the buffer
int arrayIndex = 0;                                          // Increment Variable for the buffer
int arrayIndex1=0;
int arrayIndex2=0;
int arrayIndex3=0;

//float time = 0;                                              // X axis increment variable

// Buffer for ecg,spo2,respiration,and average of thos values
float[] xdata = new float[windowSize];

double[] ch1Data = new double[windowSize];
float[] ch2Data = new float[windowSize];
float[] ch3Data = new float[windowSize];

char ch2DataTag=0;

int computed_val1 = 0;
int computed_val2 = 0;

double maxe, mine, maxr, minr, maxs, mins;             // To Calculate the Minimum and Maximum of the Buffer
double ch1, ch2, spo2_ir, spo2_red, ch3, redAvg, irAvg, ecgAvg, resAvg;  // To store the current ecg value

boolean startPlot = false;                             // Conditional Variable to start and stop the plot

GPlot plot2;
GPlot plot1;
GPlot plot3;

int step = 0;
int stepsPerCycle = 100;
int lastStepTime = 0;
boolean clockwise = true;
float scale = 5;

/************** File Related Variables **********************/

boolean logging = false;                                // Variable to check whether to record the data or not
FileWriter output;                                      // In-built writer class object to write the data to file
JFileChooser jFileChooser;                              // Helps to choose particular folder to save the file
Date date;                                              // Variables to record the date related values                              
BufferedWriter bufferedWriter;
DateFormat dateFormat;

/************** Port Related Variables **********************/

Serial port = null;                                     // Oject for communicating via serial port
String[] comList;                                       // Buffer that holds the serial ports that are paired to the laptop
char inString = '\0';                                   // To receive the bytes from the packet

String selectedPort;                                    // Holds the selected port number
String selectedBoard;

String selectedPlot1Scale; 
String selectedPlot2Scale; 
String selectedPlot3Scale;

PImage logo;
boolean gStatus;                                        // Boolean variable to save the grid visibility status

int nPoints1 = windowSize;
int totalPlotsHeight=0;
int totalPlotsWidth=0;
int heightHeader=100;
int updateCounter=0;

boolean is_raspberrypi=false;

boolean ECG_leadOff,spo2_leadOff;
boolean ShowWarning = true;
boolean ShowWarningSpo2=true;

Textlabel lblSelectedDevice;
Textlabel lblComputedVal1;
Textlabel lblComputedVal2;

Textlabel lblPlot1Scale;
Textlabel lblPlot2Scale;
Textlabel lblPlot3Scale;

boolean isRunning=false;

final static String ICON  = "logo_round.jpg";

// Main OneEuroFilter parameters
float minCutoff = 0.004; // decrease this to get rid of slow speed jitter
float beta      = 0.9;  // increase this to get rid of high speed lag

public void setup() 
{  
  GPointsArray pointsPPG = new GPointsArray(nPoints1);
  GPointsArray pointsECG = new GPointsArray(nPoints1);
  GPointsArray pointsResp = new GPointsArray(nPoints1);

  size(1024, 768, JAVA2D);
  //fullScreen();
   
  // ch
  heightHeader=100;
  println("Height:"+height);

  totalPlotsHeight=height-heightHeader;
  
  makeGUI();
  surface.setTitle("Protocentral OpenView");
  PImage icon = loadImage("logo_round.png");
  surface.setIcon(icon);
  
  plot1 = new GPlot(this);
  plot1.setPos(20,60);
  plot1.setDim(width-40, (totalPlotsHeight/3)-10);
  plot1.setBgColor(0);
  plot1.setBoxBgColor(0);
  plot1.setLineColor(color(0, 255, 0));
  plot1.setLineWidth(3);
  plot1.setMar(0,0,0,0);
  
  plot2 = new GPlot(this);
  plot2.setPos(20,(totalPlotsHeight/3+60));
  plot2.setDim(width-40, (totalPlotsHeight/3)-10);
  plot2.setBgColor(0);
  plot2.setBoxBgColor(0);
  plot2.setLineColor(color(255, 255, 0));
  plot2.setLineWidth(3);
  plot2.setMar(0,0,0,0);

  plot3 = new GPlot(this);
  plot3.setPos(20,(totalPlotsHeight/3+totalPlotsHeight/3+60));
  plot3.setDim(width-40, (totalPlotsHeight/3)-10);
  plot3.setBgColor(0);
  plot3.setBoxBgColor(0);
  plot3.setLineColor(color(0,0,255));
  plot3.setLineWidth(3);
  plot3.setMar(0,0,0,0);

  for (int i = 0; i < nPoints1; i++) 
  {
    pointsPPG.add(i,0);
    pointsECG.add(i,0);
    pointsResp.add(i,0); 
  }

  plot1.setPoints(pointsECG);
  plot2.setPoints(pointsPPG);
  plot3.setPoints(pointsPPG);


  /*******  Initializing zero for buffer ****************/

  for (int i=0; i<windowSize; i++) 
  {
    //time = time + 1;
    //xdata[i]=time;
    ch1Data[i] = 0;
    ch2Data[i] = 0;
    
  }
  
    BrainFlowInputParams params = new BrainFlowInputParams ();
    BoardIds board_id = BoardIds.SYNTHETIC_BOARD;
    //BoardShim board_shim = new BoardShim (board_id, params);
}

void changeAppIcon(PImage img) {
  final PGraphics pg = createGraphics(16, 16, JAVA2D);

  pg.beginDraw();
  pg.image(img, 0, 0, 16, 16);
  pg.endDraw();

  //frame.setIconImage(pg.image);
}

public void makeGUI()
{  
     cp5 = new ControlP5(this);
     
        
    cp5.addToggle("toggleONOFF")
     .setPosition(width-225,10)
     .setSize(100,40)
     .setValue(false)
     .setColorBackground(color(0,255,0))
      .setColorActive(color(255,0,0))
      .setCaptionLabel("START")
      .setColorLabel(0) 
      .getCaptionLabel()
      .setFont(createFont("Arial",15))
      .toUpperCase(false)
      .align(ControlP5.CENTER,ControlP5.CENTER)
     ;
  
     cp5.addButton("Record")
       .setValue(0)
       .setPosition(width-110,10)
       .setSize(100,40)
       .setFont(createFont("Arial",15))
       .addCallback(new CallbackListener() {
        public void controlEvent(CallbackEvent event) {
          if (event.getAction() == ControlP5.ACTION_RELEASED) 
          {
            RecordData();
            //cp5.remove(event.getController().getName());
          }
        }
       } 
       );
           
      cp5.addScrollableList("portName")
         .setPosition(20, 10)
         .setLabel("Select Port")
         .setSize(250, 400)
         .setFont(createFont("Arial",12))
         .setBarHeight(40)
         .setOpen(false)
         .setItemHeight(40)
         .addItems(port.list())
         .setType(ScrollableList.DROPDOWN) // currently supported DROPDOWN and LIST

       ;    
      cp5.addScrollableList("board")
       .setPosition(275, 10)
       .setSize(250, 400)
       .setFont(createFont("Arial",12))
       .setBarHeight(40)
       .setItemHeight(40)
       .setOpen(false)
       
       .addItem("ADS1292R Breakout/Shield","ads1292r")
       .addItem("ADS1293 Breakout/Shield","ads1293")
       .addItem("AFE4490 Breakout/Shield","afe4490")
       .addItem("MAX86150 Breakout","max86150")
       .addItem("Pulse Express (MAX30102/MAX32664D)","pulse-exp")
       .addItem("tinyGSR Breakout","tinyGSR")
       .addItem("MAX30003 ECG Breakout","max30003")
       .addItem("MAX30001 ECG & BioZ Breakout","max30001")
       
       .setType(ScrollableList.DROPDOWN);    

     cp5.addButton("logo")
     .setPosition(20,height-40)
     .setImages(loadImage("protocentral.png"), loadImage("protocentral.png"), loadImage("protocentral.png"))
     .updateSize();    
     
     lblComputedVal1 = cp5.addTextlabel("lbl_computer_val1")
      .setText("")
      .setPosition(width-400,height-40)
      .setColorValue(color(255,255,255))
      .setFont(createFont("verdana",20));
     
     lblComputedVal2 = cp5.addTextlabel("lbl_computer_val2")
      .setText("")
      .setPosition(width-200,height-40)
      .setColorValue(color(255,255,255))
      .setFont(createFont("verdana",20));
     
     lblSelectedDevice = cp5.addTextlabel("lblSelectedDevice")
      .setText("--")
      .setPosition(250,height-30)
      .setColorValue(color(255,255,255))
      .setFont(createFont("verdana",12));
     
     /*cp5.addScrollableList("plot1_scale")
       .setPosition(width-170, 60)
       .setSize(150, 400)
       .setFont(createFont("Arial",12))
       .setBarHeight(30)
       .setItemHeight(30)
       .setOpen(false)
       
       .setLabel("Change Scale")
       
       .addItem("6 secs","6")
       .addItem("4 secs","4")
       
       .setType(ScrollableList.DROPDOWN);
       
     cp5.addScrollableList("plot2_scale")
       .setPosition(width-170, (totalPlotsHeight/3+60))
       .setSize(150, 400)
       .setFont(createFont("Arial",12))
       .setBarHeight(30)
       .setItemHeight(30)
       .setOpen(false)
       
       .setLabel("Change Scale")
       
       .addItem("6 secs","6")
       .addItem("4 secs","4")
       
       .setType(ScrollableList.DROPDOWN);
       
      cp5.addScrollableList("plot3_scale")
       .setPosition(width-170, (totalPlotsHeight/3+totalPlotsHeight/3+60))
       .setSize(150, 400)
       .setFont(createFont("Arial",12))
       .setBarHeight(30)
       .setItemHeight(30)
       .setOpen(false)
       
       .setLabel("Change Scale")
       
       .addItem("6 secs","6")
       .addItem("4 secs","4")
       .setType(ScrollableList.DROPDOWN);
     */

     lblPlot1Scale = cp5.addTextlabel("lblPlot1Scale")
      .setText("X: 6 secs | Y: auto")
      .setPosition(20, 60)
      .setColorValue(color(255,255,255))
      .setFont(createFont("verdana",12));
      
     lblPlot2Scale = cp5.addTextlabel("lblPlot2Scale")
      .setText("X: 6 secs | Y: auto")
      .setPosition(20, (totalPlotsHeight/3+60))
      .setColorValue(color(255,255,255))
      .setFont(createFont("verdana",12));
      
     lblPlot3Scale = cp5.addTextlabel("lblPlot3Scale")
      .setText("X: 6 secs | Y: auto")
      .setPosition(20, (totalPlotsHeight/3+totalPlotsHeight/3+60))
      .setColorValue(color(255,255,255))
      .setFont(createFont("verdana",12));
      
     
}

void board(int n) {
  
    println(n, cp5.get(ScrollableList.class, "board").getItem(n));
    
    Map itemMap = cp5.get(ScrollableList.class, "board").getItem(n);
    selectedBoard = itemMap.get("value").toString();
    print(selectedBoard);
    updateDeviceStatus();
}

void plot1_scale(int n) 
{
    Map itemMap = cp5.get(ScrollableList.class, "plot1_scale").getItem(n);
    selectedPlot1Scale = itemMap.get("value").toString();    
    updatePlot1Scale();
}

void plot2_scale(int n) 
{
    Map itemMap = cp5.get(ScrollableList.class, "plot2_scale").getItem(n);
    selectedPlot2Scale = itemMap.get("value").toString();    
    updatePlot2Scale();
}

void plot3_scale(int n) 
{
    Map itemMap = cp5.get(ScrollableList.class, "plot3_scale").getItem(n);
    selectedPlot3Scale = itemMap.get("value").toString();    
    updatePlot3Scale();
}

void updateDeviceStatus()
{
    lblSelectedDevice.setText("Selected device: " + selectedBoard + " on " + selectedPort);
}

void updatePlot1Scale()
{
    lblPlot1Scale.setText("X: " + selectedPlot1Scale + " secs | Y: auto");
}

void updatePlot2Scale()
{
    lblPlot2Scale.setText("X: " + selectedPlot2Scale + " secs | Y: auto");
}

void updatePlot3Scale()
{
    lblPlot3Scale.setText("X: " + selectedPlot3Scale + " secs | Y: auto");
}

void portName(int n) {
  println(n, cp5.get(ScrollableList.class, "portName").getItem(n));
  selectedPort = cp5.get(ScrollableList.class, "portName").getItem(n).get("name").toString();
  updateDeviceStatus();
  
}

void toggleONOFF(boolean onoff) {
  if(onoff==true) {
      startSerial(selectedPort,57600);
      cp5.get(Toggle.class, "toggleONOFF").setCaptionLabel("STOP");
      cp5.get(ScrollableList.class, "portName").lock();
      cp5.get(ScrollableList.class, "board").lock();
  } else {
      if(port!=null){
        stopSerial();
        cp5.get(Toggle.class, "toggleONOFF").setCaptionLabel("START");
        cp5.get(ScrollableList.class, "portName").unlock();
        cp5.get(ScrollableList.class, "board").unlock();
      }
  }
}


public void draw() 
{
    
    
    //background(0);
    background(19,75,102);
    
    GPointsArray pointsPlot1 = new GPointsArray(nPoints1);
    GPointsArray pointsPlot2 = new GPointsArray(nPoints1);
    GPointsArray pointsPlot3 = new GPointsArray(nPoints1);
    
    if (startPlot)                             // If the condition is true, then the plotting is done
    {
      for(int i=0; i<nPoints1;i++)
      {    
        try{
        DataFilter.perform_bandpass(ch1Data, (int)128, (double)3.0,(double)50.0, 4, (int) 1, 1.0);
        }
         catch (BrainFlowError e) {
            e.printStackTrace();
        }
        
        pointsPlot1.add(i,(float)ch1Data[i]);
        pointsPlot2.add(i,ch2Data[i]); 
        pointsPlot3.add(i,ch3Data[i]);  
      }
    } 
    else                                     // Default value is set
    {
      
    }

    plot1.setPoints(pointsPlot1);
    plot2.setPoints(pointsPlot2);
    plot3.setPoints(pointsPlot3);
    
    plot1.beginDraw();
    plot1.drawBackground();
    plot1.drawLines();
    plot1.endDraw();
    
    plot2.beginDraw();
    plot2.drawBackground();
    plot2.drawLines();
    plot2.endDraw();
  
    plot3.beginDraw();
    plot3.drawBackground();
    plot3.drawLines();
    plot3.endDraw();
}

public void CloseApp() 
{
  int dialogResult = JOptionPane.showConfirmDialog (null, "Would You Like to Close The Application?");
  if (dialogResult == JOptionPane.YES_OPTION) 
  {
    try
    {
      //Runtime runtime = Runtime.getRuntime();
      //Process proc = runtime.exec("sudo shutdown -h now");
      System.exit(0);
    }
    catch(Exception e)
    {
      exit();
    }
  } else
  {
    
  }
}

public void RecordData()
{
    try
  {
    jFileChooser = new JFileChooser();
    jFileChooser.setSelectedFile(new File("log.csv"));
    jFileChooser.showSaveDialog(null);
    String filePath = jFileChooser.getSelectedFile()+"";

    if ((filePath.equals("log.txt"))||(filePath.equals("null")))
    {
    } else
    {    
      logging = true;
      date = new Date();
      output = new FileWriter(jFileChooser.getSelectedFile(), true);
      bufferedWriter = new BufferedWriter(output);
      bufferedWriter.write(date.toString()+"");
      bufferedWriter.newLine();
      bufferedWriter.write("TimeStamp,ECG,PPG");
      bufferedWriter.newLine();
    }
  }
  catch(Exception e)
  {
    println("File Not Found");
  }
}
void startSerial(String startPortName, int baud)
{
  try
  {
      port = new Serial(this,startPortName, baud);
      port.clear();
      startPlot = true;
  }
  catch(Exception e)
  {

    showMessageDialog(null, "Port not available", "Error", ERROR_MESSAGE);
    System.exit (0);
  }
}

void stopSerial()
{
  try
  {
      port.clear();
      port.stop();
      startPlot = false;
  }
  catch(Exception e)
  {

    showMessageDialog(null, "Port not available", "Alert", ERROR_MESSAGE);
    System.exit (0);
  }
}

void serialEvent (Serial blePort) 
{
  inString = blePort.readChar();
  pcProcessData(inString);
}

void pcProcessData(char rxch)
{
  switch(pc_rx_state)
  {
  case CESState_Init:
    if (rxch==CES_CMDIF_PKT_START_1)
      pc_rx_state=CESState_SOF1_Found;
    break;

  case CESState_SOF1_Found:
    if (rxch==CES_CMDIF_PKT_START_2)
      pc_rx_state=CESState_SOF2_Found;
    else
      pc_rx_state=CESState_Init;                    //Invalid Packet, reset state to init
    break;

  case CESState_SOF2_Found:
        //println("inside 3");
    pc_rx_state = CESState_PktLen_Found;
    CES_Pkt_Len = (int) rxch;
    CES_Pkt_Pos_Counter = CES_CMDIF_IND_LEN;
    CES_Data_Counter = 0;
    break;

  case CESState_PktLen_Found:
    //println("inside 4");
    CES_Pkt_Pos_Counter++;
    if (CES_Pkt_Pos_Counter < CES_CMDIF_PKT_OVERHEAD)  //Read Header
    {
      if (CES_Pkt_Pos_Counter==CES_CMDIF_IND_LEN_MSB)
        CES_Pkt_Len = (int) ((rxch<<8)|CES_Pkt_Len);
      else if (CES_Pkt_Pos_Counter==CES_CMDIF_IND_PKTTYPE)
        CES_Pkt_PktType = (int) rxch;
    } else if ( (CES_Pkt_Pos_Counter >= CES_CMDIF_PKT_OVERHEAD) && (CES_Pkt_Pos_Counter < CES_CMDIF_PKT_OVERHEAD+CES_Pkt_Len+1) )  //Read Data
    {
      if (CES_Pkt_PktType == 2)
      {
        CES_Pkt_Data_Counter[CES_Data_Counter++] = (char) (rxch);          // Buffer that assigns the data separated from the packet
      }
    } else  //All data received
    {
      if (rxch==CES_CMDIF_PKT_STOP)
      { 
        
        if(selectedBoard=="afe4490")
        {
          ces_pkt_ch1_buffer[0] = CES_Pkt_Data_Counter[0];
          ces_pkt_ch1_buffer[1] = CES_Pkt_Data_Counter[1];
          ces_pkt_ch1_buffer[2] = CES_Pkt_Data_Counter[2];
          ces_pkt_ch1_buffer[3] = CES_Pkt_Data_Counter[3];
  
          ces_pkt_ch2_buffer[0] = CES_Pkt_Data_Counter[4];
          ces_pkt_ch2_buffer[1] = CES_Pkt_Data_Counter[5];
          ces_pkt_ch2_buffer[2] = CES_Pkt_Data_Counter[6];
          ces_pkt_ch2_buffer[3] = CES_Pkt_Data_Counter[7];
          
          int data1 = ces_pkt_ch1_buffer[0] | ces_pkt_ch1_buffer[1]<<8 | ces_pkt_ch1_buffer[2]<<16 | ces_pkt_ch1_buffer[3] <<24;
          ch1=data1;
     
          int data2 = ces_pkt_ch2_buffer[0] | ces_pkt_ch2_buffer[1]<<8 | ces_pkt_ch2_buffer[2]<<16 | ces_pkt_ch2_buffer[3] <<24;
          ch2=data2;
          
          computed_val1= CES_Pkt_Data_Counter[8];
          computed_val2= CES_Pkt_Data_Counter[9];
          
          lblComputedVal1.setText("SpO2: " + computed_val1 + " %");
          lblComputedVal2.setText("HR: " + computed_val2 + " bpm");
        } 
        else if(selectedBoard=="max86150")
        {     
          ces_pkt_ch1_buffer[0] = CES_Pkt_Data_Counter[0];
          ces_pkt_ch1_buffer[1] = CES_Pkt_Data_Counter[1];
  
          ces_pkt_ch2_buffer[0] = CES_Pkt_Data_Counter[2];
          ces_pkt_ch2_buffer[1] = CES_Pkt_Data_Counter[3];
  
          ces_pkt_ch3_buffer[0] = CES_Pkt_Data_Counter[4];
          ces_pkt_ch3_buffer[1] = CES_Pkt_Data_Counter[5];
  
          int data1 = ces_pkt_ch1_buffer[0] | ces_pkt_ch1_buffer[1]<<8; //reversePacket(CES_Pkt_ECG_Counter, CES_Pkt_ECG_Counter.length-1);
          data1 <<= 16;
          data1 >>= 16;
          ch1=data1;
     
          int data2 = ces_pkt_ch2_buffer[0] | ces_pkt_ch2_buffer[1]<<8; //reversePacket(CES_Pkt_ECG_Counter, CES_Pkt_ECG_Counter.length-1);
          data2 <<= 16;
          data2 >>= 16;
          ch2 = data2;
  
          int data3 = ces_pkt_ch3_buffer[0] | ces_pkt_ch3_buffer[1]<<8; //reversePacket(CES_Pkt_ECG_Counter, CES_Pkt_ECG_Counter.length-1);
          data3 <<= 16;
          data3 >>= 16;
          ch3 = data3;
        }
        else if(selectedBoard=="pulse-exp")
        {     
          ces_pkt_ch1_buffer[0] = CES_Pkt_Data_Counter[0];
          ces_pkt_ch1_buffer[1] = CES_Pkt_Data_Counter[1];
  
          ces_pkt_ch2_buffer[0] = CES_Pkt_Data_Counter[2];
          ces_pkt_ch2_buffer[1] = CES_Pkt_Data_Counter[3];
  
          int data1 = ces_pkt_ch1_buffer[0] | ces_pkt_ch1_buffer[1]<<8; //reversePacket(CES_Pkt_ECG_Counter, CES_Pkt_ECG_Counter.length-1);
          //data1 <<= 16;
          //data1 >>= 16;
          ch1=data1;
     
          int data2 = ces_pkt_ch2_buffer[0] | ces_pkt_ch2_buffer[1]<<8; //reversePacket(CES_Pkt_ECG_Counter, CES_Pkt_ECG_Counter.length-1);
          //data2 <<= 16;
          //data2 >>= 16;
          ch2 = data2;
        }
        else if(selectedBoard=="tinyGSR")
         {
          ces_pkt_ch1_buffer[0] = CES_Pkt_Data_Counter[0];
          ces_pkt_ch1_buffer[1] = CES_Pkt_Data_Counter[1];
  
          ces_pkt_ch2_buffer[0] = CES_Pkt_Data_Counter[2];
          ces_pkt_ch2_buffer[1] = CES_Pkt_Data_Counter[3];
  
          int data1 = ces_pkt_ch1_buffer[0] | ces_pkt_ch1_buffer[1]<<8; //reversePacket(CES_Pkt_ECG_Counter, CES_Pkt_ECG_Counter.length-1);
          ch1=data1;
          print(ch1);
         }
        else if(selectedBoard=="ads1292r")
        {     
          ces_pkt_ch1_buffer[0] = CES_Pkt_Data_Counter[0];
          ces_pkt_ch1_buffer[1] = CES_Pkt_Data_Counter[1];
  
          ces_pkt_ch2_buffer[0] = CES_Pkt_Data_Counter[2];
          ces_pkt_ch2_buffer[1] = CES_Pkt_Data_Counter[3];
          
          ces_pkt_cv1_buffer[0] = CES_Pkt_Data_Counter[4];
          ces_pkt_cv1_buffer[1] = CES_Pkt_Data_Counter[5];
          
          ces_pkt_cv2_buffer[0] = CES_Pkt_Data_Counter[6];
          ces_pkt_cv2_buffer[1] = CES_Pkt_Data_Counter[7];
          
          int data1 = ces_pkt_ch1_buffer[0] | ces_pkt_ch1_buffer[1]<<8; //reversePacket(CES_Pkt_ECG_Counter, CES_Pkt_ECG_Counter.length-1);
          data1 <<= 16;
          data1 >>= 16;
          ch1=data1;
     
          int data2 = ces_pkt_ch2_buffer[0] | ces_pkt_ch2_buffer[1]<<8; //reversePacket(CES_Pkt_ECG_Counter, CES_Pkt_ECG_Counter.length-1);
          data2 <<= 16;
          data2 >>= 16;
          ch2 = data2;
          
          computed_val1 = ces_pkt_cv1_buffer[0] | ces_pkt_cv1_buffer[1]<<8; //reversePacket(CES_Pkt_ECG_Counter, CES_Pkt_ECG_Counter.length-1);
          computed_val1 <<= 16;
          computed_val1 >>= 16;
          
          computed_val2 = ces_pkt_cv2_buffer[0] | ces_pkt_cv2_buffer[1]<<8; //reversePacket(CES_Pkt_ECG_Counter, CES_Pkt_ECG_Counter.length-1);
          computed_val2 <<= 16;
          computed_val2 >>= 16;
          
          lblComputedVal1.setText("RR: " + computed_val1 + " bpm ");
          lblComputedVal2.setText("HR: " + computed_val2 + " bpm");
        }
        else if(selectedBoard=="max30003")
        {     
          ces_pkt_ch1_buffer[0] = CES_Pkt_Data_Counter[0];
          ces_pkt_ch1_buffer[1] = CES_Pkt_Data_Counter[1];
          ces_pkt_ch1_buffer[2] = CES_Pkt_Data_Counter[2];
          ces_pkt_ch1_buffer[3] = CES_Pkt_Data_Counter[3];
  
          ces_pkt_ch2_buffer[0] = CES_Pkt_Data_Counter[4];
          ces_pkt_ch2_buffer[1] = CES_Pkt_Data_Counter[5];
          ces_pkt_ch2_buffer[2] = CES_Pkt_Data_Counter[6];
          ces_pkt_ch2_buffer[3] = CES_Pkt_Data_Counter[7];
          
          ces_pkt_ch3_buffer[0] = CES_Pkt_Data_Counter[8];
          ces_pkt_ch3_buffer[1] = CES_Pkt_Data_Counter[9];
          ces_pkt_ch3_buffer[2] = CES_Pkt_Data_Counter[10];
          ces_pkt_ch3_buffer[3] = CES_Pkt_Data_Counter[11];
 
          
          int data1 = ces_pkt_ch1_buffer[0] | ces_pkt_ch1_buffer[1]<<8 | ces_pkt_ch1_buffer[2]<<16 | ces_pkt_ch1_buffer[3] <<24;
          ch1=data1;
     
          int computed_val1 = ces_pkt_ch2_buffer[0] | ces_pkt_ch2_buffer[1]<<8 | ces_pkt_ch2_buffer[2]<<16 | ces_pkt_ch2_buffer[3] <<24;
          int computed_val2 = ces_pkt_ch3_buffer[0] | ces_pkt_ch3_buffer[1]<<8 | ces_pkt_ch3_buffer[2]<<16 | ces_pkt_ch3_buffer[3] <<24;
          
          lblComputedVal1.setText("RR Interval: " + computed_val1 + " ms");
          lblComputedVal2.setText("HR: " + computed_val2 + " bpm");
        }
        else if(selectedBoard=="ads1293")
        {     
         ces_pkt_ch1_buffer[0] = CES_Pkt_Data_Counter[0];
          ces_pkt_ch1_buffer[1] = CES_Pkt_Data_Counter[1];
          ces_pkt_ch1_buffer[2] = CES_Pkt_Data_Counter[2];
          ces_pkt_ch1_buffer[3] = CES_Pkt_Data_Counter[3];
  
          ces_pkt_ch2_buffer[0] = CES_Pkt_Data_Counter[4];
          ces_pkt_ch2_buffer[1] = CES_Pkt_Data_Counter[5];
          ces_pkt_ch2_buffer[2] = CES_Pkt_Data_Counter[6];
          ces_pkt_ch2_buffer[3] = CES_Pkt_Data_Counter[7];
          
          ces_pkt_ch3_buffer[0] = CES_Pkt_Data_Counter[8];
          ces_pkt_ch3_buffer[1] = CES_Pkt_Data_Counter[9];
          ces_pkt_ch3_buffer[2] = CES_Pkt_Data_Counter[10];
          ces_pkt_ch3_buffer[3] = CES_Pkt_Data_Counter[11];
  
          //computed_val1= CES_Pkt_Data_Counter[8];
          //computed_val2= CES_Pkt_Data_Counter[9];
          
          //lblComputedVal1.setText("SpO2: " + computed_val1 + " %");
          //lblComputedVal2.setText("HR: " + computed_val2 + " bpm");
          
          int data1 = ces_pkt_ch1_buffer[0] | ces_pkt_ch1_buffer[1]<<8 | ces_pkt_ch1_buffer[2]<<16 | ces_pkt_ch1_buffer[3] <<24;
          ch1=data1;
     
          int data2 = ces_pkt_ch2_buffer[0] | ces_pkt_ch2_buffer[1]<<8 | ces_pkt_ch2_buffer[2]<<16 | ces_pkt_ch2_buffer[3] <<24;
          ch2=data2;
          
          int data3 = ces_pkt_ch3_buffer[0] | ces_pkt_ch3_buffer[1]<<8 | ces_pkt_ch3_buffer[2]<<16 | ces_pkt_ch3_buffer[3] <<24;
          ch3=data3;
        }
        else if(selectedBoard=="max30001")
        {     
         ces_pkt_ch1_buffer[0] = CES_Pkt_Data_Counter[0];
          ces_pkt_ch1_buffer[1] = CES_Pkt_Data_Counter[1];
          ces_pkt_ch1_buffer[2] = CES_Pkt_Data_Counter[2];
          ces_pkt_ch1_buffer[3] = CES_Pkt_Data_Counter[3];
  
          ces_pkt_ch2_buffer[0] = CES_Pkt_Data_Counter[4];
          ces_pkt_ch2_buffer[1] = CES_Pkt_Data_Counter[5];
          ces_pkt_ch2_buffer[2] = CES_Pkt_Data_Counter[6];
          ces_pkt_ch2_buffer[3] = CES_Pkt_Data_Counter[7];
          
          ch2DataTag=CES_Pkt_Data_Counter[8];
          
          /*ces_pkt_ch3_buffer[0] = CES_Pkt_Data_Counter[8];
          ces_pkt_ch3_buffer[1] = CES_Pkt_Data_Counter[9];
          ces_pkt_ch3_buffer[2] = CES_Pkt_Data_Counter[10];
          ces_pkt_ch3_buffer[3] = CES_Pkt_Data_Counter[11];
          */
          
          int data1 = ces_pkt_ch1_buffer[0] | ces_pkt_ch1_buffer[1]<<8 | ces_pkt_ch1_buffer[2]<<16 | ces_pkt_ch1_buffer[3] <<24;
          ch1=data1;
     
          int data2 = ces_pkt_ch2_buffer[0] | ces_pkt_ch2_buffer[1]<<8 | ces_pkt_ch2_buffer[2]<<16 | ces_pkt_ch2_buffer[3] <<24;
          ch2=data2;
          
          //int data3 = ces_pkt_ch3_buffer[0] | ces_pkt_ch3_buffer[1]<<8 | ces_pkt_ch3_buffer[2]<<16 | ces_pkt_ch3_buffer[3] <<24;
          //ch3=data3;
        }
        
        
        //time = time+1;
        //xdata[arrayIndex] = time;

        ch1Data[arrayIndex1] = (float)ch1;
        
        ch3Data[arrayIndex3] = (float)ch3;

        arrayIndex1++;
        
        arrayIndex3++;
        
        if(ch2DataTag==0x00)
        {
          ch2Data[arrayIndex2]= (float)ch2;
          arrayIndex2++;
          
        }
         
        if (arrayIndex1 == windowSize)
        {  
          arrayIndex1 = 0;
        }
        
        if (arrayIndex2 == windowSize)
        {
          arrayIndex2=0;
        }
        
        if (arrayIndex3 == windowSize)
        {
          arrayIndex3=0;
        }
        
                

        if (logging == true)
        {
          try 
          {
            date = new Date();
            dateFormat = new SimpleDateFormat("HH:mm:ss");
            bufferedWriter.write(dateFormat.format(date)+","+ch1+","+ch2+","+ch3);
            bufferedWriter.newLine();
          }
          catch(IOException e) 
          {
            println("It broke!!!");
            e.printStackTrace();
          }
        }
        pc_rx_state=CESState_Init;
      } else
      {
        pc_rx_state=CESState_Init;
      }
    }
    break;

  default:
    break;
  }
}

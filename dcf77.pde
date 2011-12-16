/* http://www.arduino.cc/playground/uploads/Main/MsTimer2.zip
 * Install it on {arduino-path}/hardware/libraries/
 */
#include  <MsTimer2.h>

//#define MODE 0 // HUMAN
#define MODE 1 // MEINBERG

static const int blink_pin = 13;

static const int dcf77_pin = 2;
static const int dcf77_int = 0; /* interrupt 0 is driven by pin 2 */

static unsigned long bit_start = 0;
static int current_bit = 0;
static int current_sample = 0;
static unsigned char bits[8];
static unsigned int samples_high;

struct {
  int hour;
  int minute;
  int second;
  int summer_time;
  int day;
  int month;
  int year;
  int day_of_week;
} date;

static inline void clear_bit(unsigned char *buf, int bit) {
  buf[bit / 8] &= ~0x80 >> (bit % 8);
}

static inline void set_bit(unsigned char *buf, int bit) {
  buf[bit / 8] |= 0x80 >> (bit % 8);
}

static inline int get_bit(unsigned char *buf, int bit) {
  return (buf[bit / 8] >> (7 - (bit % 8))) & 0x01;
}

static inline void clear_bits(void) {
  current_bit = 0;
  for (int i = 0; i < 8; i++) {
    bits[i] = 0;
  }
}

static inline void clear_samples(void) {
  current_sample = 0;
  samples_high = 0;
}

static void build_date(void)
{
  /* see http://en.wikipedia.org/wiki/DCF77 for decoding */
  
  date.summer_time = get_bit(bits,17);
  
  date.minute = get_bit(bits, 21)      +
                get_bit(bits, 22) * 2  +
                get_bit(bits, 23) * 4  +
                get_bit(bits, 24) * 8  +
                get_bit(bits, 25) * 10 +
                get_bit(bits, 26) * 20 +
                get_bit(bits, 27) * 40;
  if (date.minute > 59) {
    goto bad_date;
  }
  date.hour = get_bit(bits, 29)      +
              get_bit(bits, 30) * 2  +
              get_bit(bits, 31) * 4  +
              get_bit(bits, 32) * 8  +
              get_bit(bits, 33) * 10 +
              get_bit(bits, 34) * 20;
  if (date.hour > 23) {
    goto bad_date;
  }
            
  date.day = get_bit(bits, 36)      +
             get_bit(bits, 37) * 2  +
             get_bit(bits, 38) * 4  +
             get_bit(bits, 39) * 8  +
             get_bit(bits, 40) * 10 +
             get_bit(bits, 41) * 20;  
  if (date.day < 1 || date.day > 31) {
    goto bad_date;
  }
  
  date.day_of_week = get_bit(bits, 42)      +
                     get_bit(bits, 43) * 2  +
                     get_bit(bits, 44) * 4;
  if (date.day_of_week < 0 || date.day_of_week > 7) {
   goto bad_date;
  }
  
  date.month = get_bit(bits, 45)      +
               get_bit(bits, 46) * 2  +
               get_bit(bits, 47) * 4  +
               get_bit(bits, 48) * 8  +
               get_bit(bits, 49) * 10;
  if (date.month < 1 || date.month > 12) {
    goto bad_date;
  }
  
  date.year = get_bit(bits, 50)      +
              get_bit(bits, 51) * 2  +
              get_bit(bits, 52) * 4  +
              get_bit(bits, 53) * 8  +
              get_bit(bits, 54) * 10 +
              get_bit(bits, 55) * 20 +
              get_bit(bits, 56) * 40 +
              get_bit(bits, 57) * 80;
  if (date.year < 11) {
    goto bad_date;
  }
  return;
bad_date:
    date.day = 0;
}

static inline void add_bit(int level) {
  if (level) {
    set_bit(bits, current_bit);
  } else {
    clear_bit(bits, current_bit);
  }
  current_bit = (current_bit + 1) % 60;
  if (current_bit == 58) {
    build_date();
  }
}

static int checksum(int start, int nb)
{
  int sum = 0;
  for (int i = start; i < start + nb; i++) {
    sum += get_bit(bits, i);
  }
  return sum & 1;
}

static void printxx(int value)
{
  if (value < 10) {
    Serial.print("0");
  }
  Serial.print(value);
}

#if MODE == 0
static void dump_date(void)
{
  if (date.day == 0) {
    return;
  }
   
  switch(date.day_of_week) {
  case 1: Serial.print("lundi"); break;
  case 2: Serial.print("mardi"); break;
  case 3: Serial.print("mercredi"); break;
  case 4: Serial.print("jeudi"); break;
  case 5: Serial.print("vendredi"); break;
  case 6: Serial.print("samedi"); break;
  case 7: Serial.print("dimanche"); break;
  }
  
  Serial.print(" ");      
  
  printxx(date.day);
  Serial.print("/");
  printxx(date.month);
  Serial.print("/");
  Serial.print(2000 + date.year);
  
  Serial.print(" ");
  
  printxx(date.hour);
  Serial.print(":");
  printxx(date.minute);
  Serial.print(":");
  printxx(current_bit);
  if (date.summer_time) {
    Serial.println(" CEST");
  } else {
    Serial.println(" CET");
  }
}
#else
static void dump_date(void)
{
  if (date.day == 0) {
    return;
  }
  /* MEINBERG format for use with ntp server
   * http://www.meinberg.de/english/specs/timestr.htm
   */
  Serial.write(2); /* STX = Start of TeXt */
  Serial.print("D:");
  printxx(date.day);
  Serial.print(".");
  printxx(date.month);
  Serial.print(".");
  printxx(date.year);
  Serial.print(";T:");
  Serial.print(date.day_of_week);
  Serial.print(";U:");
  printxx(date.hour);
  Serial.print(".");
  printxx(date.minute);
  Serial.print(".");
  printxx(current_bit);
  Serial.print(";  ");
  if (date.summer_time) {
    Serial.print("S");
  } else {
    Serial.print(" ");
  }
  Serial.print(" ");
  Serial.write(3); /* ETX = End of TeXt */
}
#endif

static void dcf77_sampler(void) {
  int level;
  
  level = digitalRead(dcf77_pin);
  if (level) {
    samples_high++;
  }
  current_sample++;
  
  if (current_sample < 10) {
    return;
  }
  
  /* check first 100 ms are really up */
  if (current_sample == 10) {
    if (samples_high < 6) {
      /* we miss the second */
      noInterrupts();
      MsTimer2::stop();
      if (level) {
        bit_start = millis();
      } else {
        bit_start = 0;
      }
      interrupts();
      return;
    }
    samples_high = 0;
    return;
  }

  if (current_sample < 20) {
    return;
  }
  
  /* check first if 200 ms are up */
  
  if (samples_high < 6) {
      digitalWrite(blink_pin, LOW);
      add_bit(0);
  } else {
      digitalWrite(blink_pin, HIGH);
      add_bit(1);
  }

  MsTimer2::stop();
}

static void start_sampling(void) {
  clear_samples();
  MsTimer2::start();
}

static void stop_sampling(void) {
  MsTimer2::stop();
}

/* rising marks begin of a new bit */

static void dcf77_rising(void) {
  unsigned long time = millis();

  if (bit_start) {
    int duration = time - bit_start;

    if (duration < 950) {
      /* last bit is not over */
      return;
    }
    /* the 59th second is not sent to mark the new minute */
    if (duration > 1990) {
      clear_bits();
    }
  }
  /* new second */
  start_sampling();
  bit_start = time;
}

void setup(void) {
#if MODE == 0
  Serial.begin(9600);
#else
  Serial.begin(19200);
#endif  
  pinMode(blink_pin, OUTPUT);
  pinMode(dcf77_pin, INPUT);
  digitalWrite(dcf77_pin, HIGH); /* enable pull-up resistor */
  attachInterrupt(dcf77_int, dcf77_rising, RISING);
  MsTimer2::set(10, dcf77_sampler); /* sample every 10 ms */
}

void loop(void) {
  int level;

  delay(10);
  if (current_sample == 0) {
    dump_date();
  }
}

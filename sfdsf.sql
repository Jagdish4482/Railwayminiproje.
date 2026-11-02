-- ============================================================
-- Railway Management System: An Automated Railway Reservation
-- and Management Platform  (Oracle SQL / PL-SQL)
-- Run with: SET SERVEROUTPUT ON;
-- ============================================================

-- ---------- 1. CLEANUP (optional, for re-run) ----------
BEGIN
  FOR t IN (SELECT table_name FROM user_tables
            WHERE table_name IN ('CANCELLATION','PAYMENT','TICKET','PASSENGER','TRAIN_SCHEDULE','TRAIN','STATION')) LOOP
    EXECUTE IMMEDIATE 'DROP TABLE '||t.table_name||' CASCADE CONSTRAINTS';
  END LOOP;
  FOR s IN (SELECT sequence_name FROM user_sequences
            WHERE sequence_name IN ('SEQ_PNR','SEQ_PASSENGER','SEQ_PAYMENT','SEQ_CANCEL')) LOOP
    EXECUTE IMMEDIATE 'DROP SEQUENCE '||s.sequence_name;
  END LOOP;
END;
/

-- ---------- 2. TABLES ----------
CREATE TABLE station (
  station_id   NUMBER PRIMARY KEY,
  station_name VARCHAR2(50) NOT NULL,
  city         VARCHAR2(50)
);

CREATE TABLE train (
  train_no     NUMBER PRIMARY KEY,
  train_name   VARCHAR2(60) NOT NULL,
  source_id    NUMBER REFERENCES station(station_id),
  dest_id      NUMBER REFERENCES station(station_id),
  total_seats  NUMBER(4) NOT NULL,
  fare         NUMBER(8,2) NOT NULL
);

CREATE TABLE train_schedule (
  train_no        NUMBER REFERENCES train(train_no),
  travel_date     DATE,
  available_seats NUMBER(4),
  PRIMARY KEY (train_no, travel_date)
);

CREATE TABLE passenger (
  passenger_id NUMBER PRIMARY KEY,
  name         VARCHAR2(50) NOT NULL,
  age          NUMBER(3) CHECK (age BETWEEN 1 AND 120),
  gender       CHAR(1)   CHECK (gender IN ('M','F','O')),
  phone        VARCHAR2(10)
);

CREATE TABLE ticket (
  pnr          NUMBER PRIMARY KEY,
  passenger_id NUMBER REFERENCES passenger(passenger_id),
  train_no     NUMBER REFERENCES train(train_no),
  travel_date  DATE,
  seat_no      NUMBER(4),
  status       VARCHAR2(12) DEFAULT 'CONFIRMED'
               CHECK (status IN ('CONFIRMED','WAITING','CANCELLED')),
  booked_on    DATE DEFAULT SYSDATE
);

CREATE TABLE payment (
  payment_id NUMBER PRIMARY KEY,
  pnr        NUMBER REFERENCES ticket(pnr),
  amount     NUMBER(8,2),
  paid_on    DATE DEFAULT SYSDATE
);

CREATE TABLE cancellation (
  cancel_id     NUMBER PRIMARY KEY,
  pnr           NUMBER REFERENCES ticket(pnr),
  refund_amount NUMBER(8,2),
  cancelled_on  DATE DEFAULT SYSDATE
);

------------ 3. SEQUENCES ----------
CREATE SEQUENCE seq_pnr       START WITH 1001;
CREATE SEQUENCE seq_passenger START WITH 1;
CREATE SEQUENCE seq_payment   START WITH 1;
CREATE SEQUENCE seq_cancel    START WITH 1;

-- ---------- 4. SAMPLE DATA ----------
INSERT INTO station VALUES (1,'New Delhi','Delhi');
INSERT INTO station VALUES (2,'Chandigarh','Chandigarh');
INSERT INTO station VALUES (3,'Mumbai Central','Mumbai');
INSERT INTO station VALUES (4,'Howrah','Kolkata');

INSERT INTO train VALUES (12001,'Shatabdi Express',1,2,5,800);
INSERT INTO train VALUES (12951,'Rajdhani Express',1,3,3,2200);
INSERT INTO train VALUES (12301,'Howrah Rajdhani',1,4,4,2500);

INSERT INTO train_schedule VALUES (12001, TRUNC(SYSDATE)+1, 5);
INSERT INTO train_schedule VALUES (12951, TRUNC(SYSDATE)+1, 3);
INSERT INTO train_schedule VALUES (12301, TRUNC(SYSDATE)+2, 4);
COMMIT;
-- ---------- 5. FUNCTIONS ----------
-- 5a. Seat availability check
CREATE OR REPLACE FUNCTION fn_available_seats(p_train NUMBER, p_date DATE)
RETURN NUMBER IS
  v_seats NUMBER;
BEGIN
  SELECT available_seats INTO v_seats
  FROM train_schedule
  WHERE train_no = p_train AND travel_date = TRUNC(p_date);
  RETURN v_seats;
EXCEPTION
  WHEN NO_DATA_FOUND THEN RETURN -1;   -- no schedule
END;
/

-- 5b. Refund calculation (cancellation rules)
--     >= 2 days before: 80% | 1 day before: 50% | same day: 25%
CREATE OR REPLACE FUNCTION fn_refund(p_pnr NUMBER)
RETURN NUMBER IS
  v_fare   NUMBER;
  v_date   DATE;
  v_days   NUMBER;
BEGIN
  SELECT tr.fare, t.travel_date INTO v_fare, v_date
  FROM ticket t JOIN train tr ON t.train_no = tr.train_no
  WHERE t.pnr = p_pnr;

  v_days := TRUNC(v_date) - TRUNC(SYSDATE);
  IF    v_days >= 2 THEN RETURN v_fare * 0.80;
  ELSIF v_days  = 1 THEN RETURN v_fare * 0.50;
  ELSE                   RETURN v_fare * 0.25;
  END IF;
END;
/

-- ---------- 6. PROCEDURES ----------
-- 6a. Book ticket (with automatic waiting-list handling)
CREATE OR REPLACE PROCEDURE sp_book_ticket(
  p_name VARCHAR2, p_age NUMBER, p_gender CHAR, p_phone VARCHAR2,
  p_train NUMBER, p_date DATE)
IS
  v_pid    NUMBER;
  v_pnr    NUMBER;
  v_seats  NUMBER;
  v_total  NUMBER;
  v_fare   NUMBER;
  v_status VARCHAR2(12);
  v_seatno NUMBER;
BEGIN
  v_seats := fn_available_seats(p_train, p_date);
  IF v_seats = -1 THEN
    RAISE_APPLICATION_ERROR(-20001,'Train not running on this date');
  END IF;

  SELECT total_seats, fare INTO v_total, v_fare FROM train WHERE train_no = p_train;

  INSERT INTO passenger VALUES (seq_passenger.NEXTVAL, p_name, p_age, p_gender, p_phone)
  RETURNING passenger_id INTO v_pid;

  v_pnr := seq_pnr.NEXTVAL;

  IF v_seats > 0 THEN
    v_status := 'CONFIRMED';
    v_seatno := v_total - v_seats + 1;
    UPDATE train_schedule SET available_seats = available_seats - 1
    WHERE train_no = p_train AND travel_date = TRUNC(p_date);
  ELSE
    v_status := 'WAITING';
    v_seatno := NULL;
  END IF;

  INSERT INTO ticket (pnr, passenger_id, train_no, travel_date, seat_no, status)
  VALUES (v_pnr, v_pid, p_train, TRUNC(p_date), v_seatno, v_status);

  IF v_status = 'CONFIRMED' THEN
    INSERT INTO payment VALUES (seq_payment.NEXTVAL, v_pnr, v_fare, SYSDATE);
  END IF;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('PNR: '||v_pnr||' | Status: '||v_status||
                       ' | Seat: '||NVL(TO_CHAR(v_seatno),'-')||' | Fare: '||v_fare);
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('Booking failed: '||SQLERRM);
END;
/

-- 6b. Cancel ticket (refund + promote first waiting passenger)
CREATE OR REPLACE PROCEDURE sp_cancel_ticket(p_pnr NUMBER) IS
  v_status  ticket.status%TYPE;
  v_train   ticket.train_no%TYPE;
  v_date    ticket.travel_date%TYPE;
  v_seat    ticket.seat_no%TYPE;
  v_refund  NUMBER;
  v_wl_pnr  NUMBER;
BEGIN
  SELECT status, train_no, travel_date, seat_no
  INTO v_status, v_train, v_date, v_seat
  FROM ticket WHERE pnr = p_pnr;

  IF v_status = 'CANCELLED' THEN
    DBMS_OUTPUT.PUT_LINE('Ticket already cancelled.');
    RETURN;
  END IF;

  v_refund := CASE WHEN v_status = 'CONFIRMED' THEN fn_refund(p_pnr) ELSE 0 END;

  UPDATE ticket SET status = 'CANCELLED', seat_no = NULL WHERE pnr = p_pnr;
  INSERT INTO cancellation VALUES (seq_cancel.NEXTVAL, p_pnr, v_refund, SYSDATE);

  IF v_status = 'CONFIRMED' THEN
    -- give freed seat to earliest waiting passenger, else free the seat
    BEGIN
      SELECT pnr INTO v_wl_pnr FROM (
        SELECT pnr FROM ticket
        WHERE train_no = v_train AND travel_date = v_date AND status = 'WAITING'
        ORDER BY booked_on, pnr)
      WHERE ROWNUM = 1;

      UPDATE ticket SET status = 'CONFIRMED', seat_no = v_seat WHERE pnr = v_wl_pnr;
      DBMS_OUTPUT.PUT_LINE('Waiting PNR '||v_wl_pnr||' is now CONFIRMED.');
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        UPDATE train_schedule SET available_seats = available_seats + 1
        WHERE train_no = v_train AND travel_date = v_date;
    END;
  END IF;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('PNR '||p_pnr||' cancelled. Refund: '||v_refund);
EXCEPTION
  WHEN NO_DATA_FOUND THEN DBMS_OUTPUT.PUT_LINE('Invalid PNR.');
END;
/

-- 6c. PNR status enquiry
CREATE OR REPLACE PROCEDURE sp_pnr_status(p_pnr NUMBER) IS
BEGIN
  FOR r IN (SELECT t.pnr, p.name, tr.train_name, t.travel_date, t.seat_no, t.status
            FROM ticket t
            JOIN passenger p ON p.passenger_id = t.passenger_id
            JOIN train tr    ON tr.train_no = t.train_no
            WHERE t.pnr = p_pnr) LOOP
    DBMS_OUTPUT.PUT_LINE('PNR: '||r.pnr||' | '||r.name||' | '||r.train_name||
      ' | '||TO_CHAR(r.travel_date,'DD-MON-YYYY')||' | Seat: '||NVL(TO_CHAR(r.seat_no),'-')||
      ' | '||r.status);
  END LOOP;
END;
/

-- 6d. Train-wise passenger list using an explicit cursor
CREATE OR REPLACE PROCEDURE sp_passenger_list(p_train NUMBER, p_date DATE) IS
  CURSOR c IS
    SELECT p.name, p.age, t.seat_no, t.status
    FROM ticket t JOIN passenger p ON p.passenger_id = t.passenger_id
    WHERE t.train_no = p_train AND t.travel_date = TRUNC(p_date)
    ORDER BY t.seat_no;
BEGIN
  DBMS_OUTPUT.PUT_LINE('--- Passenger List: Train '||p_train||' ---');
  FOR r IN c LOOP
    DBMS_OUTPUT.PUT_LINE(RPAD(r.name,20)||RPAD(r.age,5)||
                         RPAD(NVL(TO_CHAR(r.seat_no),'WL'),6)||r.status);
  END LOOP;
END;
/

-- ---------- 7. TRIGGERS ----------
-- 7a. Block booking for past dates
CREATE OR REPLACE TRIGGER trg_no_past_booking
BEFORE INSERT ON ticket
FOR EACH ROW
BEGIN
  IF :NEW.travel_date < TRUNC(SYSDATE) THEN
    RAISE_APPLICATION_ERROR(-20002,'Cannot book ticket for a past date');
  END IF;
END;
/

-- 7b. Audit log for cancellations
CREATE TABLE ticket_audit (
  pnr NUMBER, old_status VARCHAR2(12), new_status VARCHAR2(12), changed_on DATE
);

CREATE OR REPLACE TRIGGER trg_ticket_audit
AFTER UPDATE OF status ON ticket
FOR EACH ROW
BEGIN
  INSERT INTO ticket_audit VALUES (:OLD.pnr, :OLD.status, :NEW.status, SYSDATE);
END;
/

-- ---------- 8. DEMO RUN ----------
SET SERVEROUTPUT ON;
BEGIN
  sp_book_ticket('Rahul Sharma', 25,'M','9876543210',12951,SYSDATE+1);
  sp_book_ticket('Priya Verma',  22,'F','9876500000',12951,SYSDATE+1);
  sp_book_ticket('Amit Kumar',   40,'M','9811122233',12951,SYSDATE+1);
  sp_book_ticket('Neha Singh',   30,'F','9999988888',12951,SYSDATE+1); -- goes to WAITING
END;
/
EXEC sp_pnr_status(1001);
EXEC sp_passenger_list(12951, SYSDATE+1);
EXEC sp_cancel_ticket(1001);       -- refund + waiting list promotion
EXEC sp_passenger_list(12951, SYSDATE+1);

-- ---------- 9. REPORT QUERIES ----------
-- Total revenue per train
SELECT tr.train_name, SUM(p.amount) AS revenue
FROM payment p JOIN ticket t ON p.pnr = t.pnr
JOIN train tr ON tr.train_no = t.train_no
GROUP BY tr.train_name;

-- Cancellation report
SELECT c.pnr, c.refund_amount, c.cancelled_on FROM cancellation c;

-- Trains running between two stations
SELECT t.train_no, t.train_name, s1.station_name AS source, s2.station_name AS destination, t.fare
FROM train t JOIN station s1 ON s1.station_id = t.source_id
             JOIN station s2 ON s2.station_id = t.dest_id;